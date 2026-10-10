import asyncio
import json
import re
import os
import signal
import sys
from datetime import datetime

from telethon import TelegramClient, events
from telethon.sessions import StringSession
from telethon.errors import (
    SessionPasswordNeededError,
    FloodWaitError,
    AuthKeyUnregisteredError,
    AuthKeyDuplicatedError,
    UserDeactivatedBanError,
)
from telethon.tl.functions.channels import LeaveChannelRequest
from telethon.tl.functions.messages import DeleteChatUserRequest

from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.constants import ParseMode
from telegram.request import HTTPXRequest
from telegram.ext import (
    Application, CommandHandler, CallbackQueryHandler,
    ContextTypes, MessageHandler, filters
)

BOT_TOKEN = ""
OWNER_ID   = 93496624
API_ID     = 
API_HASH   = ""

DATA_FILE = "bot_data.json"
VIDEO_URL = "https://c.top4top.io/m_3781s2t9v1.mp4"

FATAL_SESSION_ERRORS = (
    AuthKeyUnregisteredError,
    AuthKeyDuplicatedError,
    UserDeactivatedBanError,
)

active_monitors: dict[int, TelegramClient] = {}
monitor_tasks:   dict[int, asyncio.Task]   = {}


def load_data() -> dict:
    if not os.path.exists(DATA_FILE):
        return {"users": {}, "allowed": []}
    with open(DATA_FILE, "r", encoding="utf-8") as f:
        return json.load(f)

def save_data(data: dict) -> None:
    with open(DATA_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

def get_user(user_id: int) -> dict | None:
    return load_data()["users"].get(str(user_id))

def set_user(user_id: int, phone: str, session_string: str, frozen: bool = False) -> None:
    data = load_data()
    data["users"][str(user_id)] = {
        "phone":          phone,
        "session_string": session_string,
        "added_at":       datetime.now().isoformat(),
        "frozen":         frozen,
    }
    save_data(data)

def delete_user(user_id: int) -> None:
    data = load_data()
    if str(user_id) in data["users"]:
        del data["users"][str(user_id)]
        save_data(data)

def is_allowed(user_id: int) -> bool:
    if user_id == OWNER_ID:
        return True
    data = load_data()
    allowed = data.get("allowed", [])
    return str(user_id) in [str(x) for x in allowed]

def add_allowed_user(user_id: int) -> None:
    data = load_data()
    if "allowed" not in data:
        data["allowed"] = []
    if str(user_id) not in [str(x) for x in data["allowed"]]:
        data["allowed"].append(str(user_id))
        save_data(data)

def remove_allowed_user(user_id: int) -> None:
    data = load_data()
    lst  = data.get("allowed", [])
    new_lst = [x for x in lst if str(x) != str(user_id)]
    data["allowed"] = new_lst
    save_data(data)

def list_allowed_users() -> list[int]:
    return [int(uid) for uid in load_data().get("allowed", [])]

def add_log(user_id: int, event: str, details: str) -> None:
    with open("activity.log", "a", encoding="utf-8") as f:
        f.write(f"{datetime.now().isoformat()} | User {user_id} | {event} | {details}\n")

def _make_client(session_string: str = "") -> TelegramClient:
    """
    Create a TelegramClient configured for long-term (months-long) connections.
    - connection_retries=-1  : retry forever on transient failures
    - auto_reconnect=True    : built-in reconnect (default, but explicit)
    - flood_sleep_threshold  : auto-sleep on small flood waits
    - request_retries        : retry individual MTProto requests
    """
    return TelegramClient(
        StringSession(session_string),
        API_ID,
        API_HASH,
        connection_retries=-1,
        retry_delay=5,
        auto_reconnect=True,
        flood_sleep_threshold=60,
        request_retries=5,
        device_model="Desktop",
        system_version="Windows 10",
        app_version="1.0.0",
        lang_code="en",
        system_lang_code="en",
    )

async def get_telegram_chat(client: TelegramClient):
    """Get the official Telegram service entity (777000)."""
    for target in (777000, "telegram"):
        try:
            return await client.get_entity(target)
        except Exception:
            pass
    return None

def _extract_chat_info(text: str) -> tuple[str, str]:
    """
    Extract channel/group name and type from an ownership-transfer message.
    Returns (name, type) where type is 'قناة' or 'كروب'.

    Supported Telegram message patterns:
      EN channel: "Do you want to transfer ownership of the channel «Name» to ..."
      EN group  : "Do you want to transfer ownership of the group «Name» to ..."
      AR channel: "هل تريد نقل ملكية القناة «الاسم» إلى ..."
      AR group  : "هل تريد نقل ملكية المجموعة «الاسم» إلى ..."
    """
    type_rules = [
        (r'\bchannel\b',          "قناة"),
        (r'قناة|القناة|channels', "قناة"),
        (r'\bgroup\b',            "كروب"),
        (r'مجموع[ةه]|المجموع[ةه]|groups', "كروب"),
        (r'\bsupergroup\b',       "كروب"),
    ]
    chat_type = "كروب"
    for pattern, ctype in type_rules:
        if re.search(pattern, text, re.IGNORECASE):
            chat_type = ctype
            break

    name_patterns = [
        r'«\s*(.+?)\s*»',
        r'\u201c\s*(.+?)\s*\u201d',
        r'"\s*(.+?)\s*"',
        r"'\s*(.+?)\s*'",
        r'ownership\s+of\s+the\s+channel\s+(.+?)\s+to\b',
        r'ownership\s+of\s+the\s+group\s+(.+?)\s+to\b',
        r'ownership\s+of\s+the\s+supergroup\s+(.+?)\s+to\b',
        r'ملكية\s+القناة\s+(.+?)\s+إلى',
        r'ملكية\s+المجموع[ةه]\s+(.+?)\s+إلى',
        r'\bchannel\s+["\u00ab]?(.+?)["\u00bb]?\s+to\b',
        r'\bgroup\s+["\u00ab]?(.+?)["\u00bb]?\s+to\b',
    ]
    for pat in name_patterns:
        m = re.search(pat, text, re.IGNORECASE | re.DOTALL)
        if m:
            name = m.group(1).strip()
            if name:
                return name, chat_type

    first_line = text.strip().splitlines()[0] if text.strip() else "unknown"
    return first_line[:60], chat_type


def _format_time_12h(dt: datetime) -> str:
    """Format datetime as 12-hour clock with Arabic AM/PM."""
    hour   = dt.hour
    minute = dt.strftime("%M")
    period = "ص" if hour < 12 else "م"
    hour12 = hour % 12
    if hour12 == 0:
        hour12 = 12
    day   = dt.strftime("%d")
    month = dt.strftime("%m")
    year  = dt.strftime("%Y")
    return f"{day}/{month}/{year} الساعة {hour12:02d}:{minute} {period}"

async def _try_leave_chat(client: TelegramClient, chat_name: str, user_id: int) -> bool:
    """
    Attempt to leave a channel/group after rejecting an ownership transfer.
    Tries get_entity by name first, then searches dialogs.
    """
    entity = None

    try:
        entity = await client.get_entity(chat_name)
    except Exception:
        pass

    if entity is None:
        try:
            async for dialog in client.iter_dialogs():
                if dialog.title and chat_name.lower() in dialog.title.lower():
                    entity = dialog.entity
                    break
        except Exception:
            pass

    if entity is None:
        add_log(user_id, "leave_skipped", f"Entity not found: {chat_name}")
        return False

    try:
        await client(LeaveChannelRequest(entity))
        add_log(user_id, "left_chat", f"Left channel/group: {chat_name}")
        return True
    except Exception:
        pass

    try:
        await client(DeleteChatUserRequest(entity.id, "me"))
        add_log(user_id, "left_chat", f"Left group: {chat_name}")
        return True
    except Exception as e:
        add_log(user_id, "leave_failed", f"Failed to leave {chat_name}: {e}")
        return False

async def _notify_user(user_id: int, client: TelegramClient, text: str) -> None:
    """Send a notification to the user via bot, with Saved Messages as fallback."""
    try:
        await app.bot.send_message(chat_id=user_id, text=text)
    except Exception:
        try:
            await client.send_message("me", text)
        except Exception:
            pass

async def _invalidate_session(user_id: int, reason: str) -> None:
    """
    Clean up a broken session:
    - Delete user data from file
    - Notify user to re-login
    """
    add_log(user_id, "session_invalid", reason)
    delete_user(user_id)
    try:
        await app.bot.send_message(
            chat_id=user_id,
            text=(
                "انتهت صلاحية جلستك او اصبحت غير صالحة!\n\n"
                f"السبب: {reason}\n\n"
                "يرجى الضغط على /start ثم تسجيل الدخول من جديد."
            ),
        )
    except Exception:
        pass

async def _keepalive_task(client: TelegramClient, user_id: int) -> None:
    """
    Periodic keepalive ping to prevent the server from dropping an idle connection.
    Runs every 4 minutes. Silently exits only when cancelled.
    """
    PING_INTERVAL = 240
    while True:
        try:
            await asyncio.sleep(PING_INTERVAL)
            if client.is_connected():
                await client.get_me()
                print(f"[{user_id}] Keepalive ping OK")
        except asyncio.CancelledError:
            break
        except Exception as e:
            print(f"[{user_id}] Keepalive ping failed (will retry): {e}")


async def _monitor_loop(user_id: int, session_string: str) -> None:
    """
    Permanent monitoring loop that automatically reconnects on any disconnection.
    Stops only when:
      - The task is deliberately cancelled (session cleared)
      - A fatal unrecoverable session error occurs
    """
    retry_delay = 5
    MAX_DELAY   = 300

    while True:
        client        = None
        keepalive     = None
        fatal         = False

        try:
            user_data = get_user(user_id)
            if not user_data:
                print(f"[{user_id}] No session found — stopping monitor.")
                break

            print(f"[{user_id}] Connecting...")
            client = _make_client(session_string)

            try:
                await asyncio.wait_for(client.connect(), timeout=60)
            except asyncio.TimeoutError:
                print(f"[{user_id}] Connection timed out — will retry.")
                raise ConnectionError("connect() timed out")

            if not await client.is_user_authorized():
                print(f"[{user_id}] Session unauthorized.")
                await _invalidate_session(user_id, "Session expired or revoked in the app")
                fatal = True
                break

            active_monitors[user_id] = client

            @client.on(events.NewMessage(incoming=True, chats=777000))
            async def handler(event, _uid=user_id, _client=client):
                if event.out:
                    return
                u = get_user(_uid)
                if not u or u.get("frozen"):
                    return
                msg = event.message
                if not (msg.raw_text and msg.buttons):
                    return

                add_log(_uid, "transfer_detected", "Ownership transfer attempt detected")
                chat_name, chat_type = _extract_chat_info(msg.raw_text)

                try:
                    await msg.buttons[0][0].click()
                    add_log(_uid, "transfer_rejected", f"Rejected transfer: {chat_name}")
                    now  = datetime.now()

                    left = await _try_leave_chat(_client, chat_name, _uid)
                    leave_note = "\nتم الخروج من القناة/الكروب تلقائياً" if left else ""

                    notif = (
                        f"تم الحماية ورفض ملكية لـ {chat_type} ({chat_name})\n"
                        f"{'─' * 15}\n"
                        f"في {_format_time_12h(now)}\n"
                        f"الحالة : تم الرفض تلقائياً{leave_note}\n"
                        f"السبب  : نقل بدون علم صاحب الحساب"
                    )
                    await _notify_user(_uid, _client, notif)

                except FloodWaitError as fw:
                    add_log(_uid, "transfer_flood", f"Flood wait: {fw.seconds}s")
                    await asyncio.sleep(fw.seconds)
                except Exception as ex:
                    add_log(_uid, "transfer_click_failed", str(ex))

            print(f"[{user_id}] Monitor running 24/7")
            retry_delay = 5

            keepalive = asyncio.get_running_loop().create_task(
                _keepalive_task(client, user_id),
                name=f"keepalive_{user_id}",
            )

            await client.run_until_disconnected()

            print(f"[{user_id}] Disconnected — retrying in {retry_delay}s")

        except asyncio.CancelledError:
            print(f"[{user_id}] Monitor stopped intentionally.")
            break

        except FATAL_SESSION_ERRORS as fe:
            print(f"[{user_id}] Fatal session error: {fe}")
            await _invalidate_session(user_id, str(fe))
            fatal = True
            break

        except Exception as e:
            err = str(e)
            if "key is not registered" in err.lower() or "auth_key_unregistered" in err.lower():
                print(f"[{user_id}] Unregistered auth key (broken session): {e}")
                await _invalidate_session(user_id, "Auth key not registered — please re-login")
                fatal = True
                break
            add_log(user_id, "monitor_error", err)
            print(f"[{user_id}] Error: {e} | Retrying in {retry_delay}s")

        finally:
            if keepalive and not keepalive.done():
                keepalive.cancel()
                try:
                    await keepalive
                except asyncio.CancelledError:
                    pass

            if client:
                try:
                    await client.disconnect()
                except Exception:
                    pass
            active_monitors.pop(user_id, None)

        if fatal:
            break

        await asyncio.sleep(retry_delay)
        retry_delay = min(retry_delay * 2, MAX_DELAY)


def start_monitoring(user_id: int, session_string: str) -> None:
    """Start the monitoring loop as a background task."""
    old = monitor_tasks.get(user_id)
    if old and not old.done():
        old.cancel()

    task = asyncio.get_running_loop().create_task(
        _monitor_loop(user_id, session_string),
        name=f"monitor_{user_id}",
    )
    monitor_tasks[user_id] = task

def stop_monitoring(user_id: int) -> None:
    """Cancel the monitoring task and clean up memory."""
    task = monitor_tasks.pop(user_id, None)
    if task and not task.done():
        task.cancel()
    active_monitors.pop(user_id, None)

_request = HTTPXRequest(
    connection_pool_size=8,
    connect_timeout=30.0,
    read_timeout=30.0,
    write_timeout=30.0,
    pool_timeout=30.0,
)
app = Application.builder().token(BOT_TOKEN).request(_request).build()

LOGIN_PHONE, LOGIN_CODE, LOGIN_PASSWORD, MANAGE_ADD_USER = range(4)

async def _send_start_video(target, text: str, markup, parse_mode=ParseMode.HTML, query=None) -> None:
    """Send/edit the welcome message with video; falls back to text."""
    if query is not None:
        try:
            await query.edit_message_caption(
                caption=text,
                reply_markup=markup,
                parse_mode=parse_mode,
            )
            return
        except Exception:
            pass
        try:
            await query.edit_message_text(
                text=text,
                reply_markup=markup,
                parse_mode=parse_mode,
            )
            return
        except Exception:
            pass
    try:
        await target.reply_animation(
            animation=VIDEO_RL,
            caption=text,
            reply_markup=markup,
            parse_mode=parse_mode,
        )
    except Exception:
        try:
            await target.reply_text(text, reply_markup=markup, parse_mode=parse_mode)
        except Exception:
            pass

async def safe_edit(query, text: str, keyboard=None, parse_mode=ParseMode.HTML) -> None:
    """
    Safely edit a callback message:
    1) edit_message_text
    2) edit_message_caption
    3) reply_text as fallback
    """
    kwargs = {"reply_markup": keyboard, "parse_mode": parse_mode}

    try:
        await query.edit_message_text(text, **kwargs)
        return
    except Exception:
        pass

    try:
        await query.edit_message_caption(caption=text, **kwargs)
        return
    except Exception:
        pass

    try:
        await query.message.reply_text(text, **kwargs)
    except Exception:
        pass

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    user      = update.effective_user
    user_id   = user.id

    full_name    = (user.full_name or user.first_name or "مستخدم").strip()
    user_display = f'<a href="tg://user?id={user_id}">{full_name}</a>'

    target = update.callback_query.message if update.callback_query else update.message
    cq     = update.callback_query

    if not is_allowed(user_id):
        await _send_start_video(
            target,
            f"مرحبا {user_display}\n\nعذرا، لا يمكنك استخدام هذا البوت.\nللاشتراك تواصل مع المطور.",
            InlineKeyboardMarkup([[InlineKeyboardButton("تواصل مع المطور", url="https://t.me/isMohnd")]]),
            query=cq,
        )
        return

    welcome = (
        f"مرحبا {user_display} في بوت حماية الحسابات من نقل الملكية الخاص بـ hell\n"
        "---------------------------------\n\n"
        "تنبيه قبل تسجيل دخول الى البوت عليك القيام بهذه الامور\n"
        "1- قم باضافة حساب الـ Telegram الرسمي بجهات الاتصال\n"
        "2- لا تعدل اسم الحساب ابدا ولا يجب ان يكون هناك جهة اتصال بنفس الاسم\n\n"
        "---------------------------------\n"
        "Dev. - @isMohnd"
    )
    keyboard = [
        [InlineKeyboardButton("تسجيل الدخول الى حسابك", callback_data="login")],
        [InlineKeyboardButton("حالة الحماية",            callback_data="status")],
        [InlineKeyboardButton("فحص الاشعارات القديمة",  callback_data="scan")],
        [InlineKeyboardButton("مسح الجلسة",              callback_data="clear")],
    ]
    if user_id == OWNER_ID:
        keyboard.append([InlineKeyboardButton("ادارة المستخدمين", callback_data="manage")])

    await _send_start_video(target, welcome, InlineKeyboardMarkup(keyboard), query=cq)


async def button_callback(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    query   = update.callback_query
    await query.answer()
    user_id = update.effective_user.id
    data    = query.data

    if data == "login":
        if get_user(user_id):
            await safe_edit(
                query,
                "لديك جلسة محفوظة. استخدم مسح الجلسة اولا.",
                keyboard=InlineKeyboardMarkup([[InlineKeyboardButton("رجوع", callback_data="main")]]),
            )
        else:
            await safe_edit(
                query,
                "ارسل رقم هاتفك مع رمز الدولة.\nمثال: +9661234567890",
                keyboard=InlineKeyboardMarkup([[InlineKeyboardButton("إلغاء", callback_data="main")]]),
            )
            context.user_data["login_state"] = LOGIN_PHONE

    elif data == "clear":
        stop_monitoring(user_id)
        delete_user(user_id)
        add_log(user_id, "session_cleared", "Session cleared by user")
        await safe_edit(
            query, "تم مسح الجلسة بنجاح.",
            keyboard=InlineKeyboardMarkup([[InlineKeyboardButton("رجوع", callback_data="main")]]),
        )

    elif data == "status":
        ud = get_user(user_id)
        if not ud:
            await safe_edit(
                query, "لم تقم بتسجيل الدخول بعد.",
                keyboard=InlineKeyboardMarkup([[InlineKeyboardButton("رجوع", callback_data="main")]]),
            )
            return

        frozen = ud.get("frozen", False)

        if not frozen:
            status_text = (
                "حالة الحماية:\n"
                "• الجلسة   : موجودة\n"
                "• الحماية  : تعمل\n\n"
                "لجعل البوت لا يرفض الملكية مؤقتاً قم بتجميده :"
            )
            freeze_btn = InlineKeyboardButton("تجميد البوت", callback_data="freeze")
        else:
            status_text = (
                "حالة الحماية:\n"
                "• الجلسة   : موجودة\n"
                "• الحماية  : لا تعمل\n\n"
                "تم تجميد البوت من رفض الملكية\n"
                "لارجاع الحماية قم بالغاء التجميد :"
            )
            freeze_btn = InlineKeyboardButton("الغاء تجميد البوت", callback_data="freeze")

        await safe_edit(
            query, status_text,
            keyboard=InlineKeyboardMarkup([
                [freeze_btn],
                [InlineKeyboardButton("رجوع", callback_data="main")],
            ]),
        )

    elif data == "freeze":
        ud = get_user(user_id)
        if not ud:
            await safe_edit(query, "لا توجد جلسة نشطة.")
            return

        new_frozen = not ud.get("frozen", False)
        full = load_data()
        full["users"][str(user_id)]["frozen"] = new_frozen
        save_data(full)
        add_log(user_id, "freeze_toggle", "frozen" if new_frozen else "active")

        if not new_frozen:
            status_text = (
                "حالة الحماية:\n"
                "• الجلسة   : موجودة\n"
                "• الحماية  : تعمل\n\n"
                "لجعل البوت لا يرفض الملكية مؤقتاً قم بتجميده :"
            )
            freeze_btn = InlineKeyboardButton("تجميد البوت", callback_data="freeze")
        else:
            status_text = (
                "حالة الحماية:\n"
                "• الجلسة   : موجودة\n"
                "• الحماية  : لا تعمل\n\n"
                "تم تجميد البوت من رفض الملكية\n"
                "لارجاع الحماية قم بالغاء التجميد :"
            )
            freeze_btn = InlineKeyboardButton("الغاء تجميد البوت", callback_data="freeze")

        await safe_edit(
            query, status_text,
            keyboard=InlineKeyboardMarkup([
                [freeze_btn],
                [InlineKeyboardButton("رجوع", callback_data="main")],
            ]),
        )

    elif data == "scan":
        ud = get_user(user_id)
        if not ud:
            await safe_edit(
                query, "يجب تسجيل الدخول اولا.",
                keyboard=InlineKeyboardMarkup([[InlineKeyboardButton("رجوع", callback_data="main")]]),
            )
            return
        await safe_edit(
            query,
            "انتبه : اذا قمت بالتاكيد سوف يرفض جميع الملكيات السابقة المحولة لك ويُعيدها لاصحابها القديمين",
            keyboard=InlineKeyboardMarkup([
                [InlineKeyboardButton("تاكيد الفحص", callback_data="scan_confirm")],
                [InlineKeyboardButton("رجوع للقائمة الرئيسية", callback_data="main")],
            ]),
        )

    elif data == "scan_confirm":
        ud = get_user(user_id)
        if not ud:
            await safe_edit(query, "يجب تسجيل الدخول اولا.")
            return

        client = _make_client(ud["session_string"])
        try:
            await client.connect()

            if not await client.is_user_authorized():
                await _invalidate_session(user_id, "Session expired during scan")
                await safe_edit(query, "جلستك فاسدة. تم مسحها تلقائيا. اعد تسجيل الدخول.")
                return

            chat = await get_telegram_chat(client)
            if not chat:
                await safe_edit(
                    query,
                    "لم يعثر على محادثة Telegram الرسمية.\n"
                    "اضف @telegram لجهات الاتصال ثم اعد المحاولة.",
                    keyboard=InlineKeyboardMarkup([[InlineKeyboardButton("رجوع", callback_data="main")]]),
                )
                return

            count = 0
            async for msg in client.iter_messages(chat, limit=200):
                if msg.raw_text and msg.buttons:
                    try:
                        chat_name, _ = _extract_chat_info(msg.raw_text)
                        await msg.buttons[0][0].click()
                        await _try_leave_chat(client, chat_name, user_id)
                        count += 1
                        await asyncio.sleep(0.5)
                    except Exception:
                        pass

            await safe_edit(
                query,
                f"فحص مكتمل — تم رفض {count} محاولة نقل ملكية.",
                keyboard=InlineKeyboardMarkup([[InlineKeyboardButton("رجوع للقائمة الرئيسية", callback_data="main")]]),
            )

        except FATAL_SESSION_ERRORS as fe:
            await _invalidate_session(user_id, str(fe))
            await safe_edit(query, "جلستك فاسدة. تم مسحها. اعد تسجيل الدخول.")
        except Exception as e:
            await safe_edit(query, f"خطا اثناء الفحص: {e}")
        finally:
            try:
                await client.disconnect()
            except Exception:
                pass

    elif data == "manage":
        if user_id != OWNER_ID:
            await safe_edit(query, "غير مصرح لك.")
            return
        users = list_allowed_users()
        count = len(users)
        await safe_edit(
            query,
            f"لوحة ادارة المستخدمين\n"
            f"---------------------------------\n"
            f"عدد المستخدمين المصرح لهم: {count}",
            keyboard=InlineKeyboardMarkup([
                [InlineKeyboardButton("اضافة مستخدم",    callback_data="manage_add")],
                [InlineKeyboardButton("حذف مستخدم",      callback_data="manage_remove")],
                [InlineKeyboardButton("عرض المستخدمين",  callback_data="manage_list")],
                [InlineKeyboardButton("رجوع",             callback_data="main")],
            ]),
        )

    elif data == "manage_add":
        if user_id != OWNER_ID:
            await safe_edit(query, "غير مصرح لك.")
            return
        context.user_data["login_state"] = MANAGE_ADD_USER
        await safe_edit(
            query,
            "ارسل معرف المستخدم (ID) الذي تريد اضافته.\n"
            "مثال: 123456789",
            keyboard=InlineKeyboardMarkup([[InlineKeyboardButton("الغاء", callback_data="manage")]]),
        )

    elif data == "manage_remove":
        if user_id != OWNER_ID:
            await safe_edit(query, "غير مصرح لك.")
            return
        users = list_allowed_users()
        if not users:
            await safe_edit(
                query,
                "لا يوجد مستخدمون لحذفهم.",
                keyboard=InlineKeyboardMarkup([[InlineKeyboardButton("رجوع", callback_data="manage")]]),
            )
            return
        rows = []
        for uid in users:
            rows.append([InlineKeyboardButton(f"حذف: {uid}", callback_data=f"mdel_{uid}")])
        rows.append([InlineKeyboardButton("رجوع", callback_data="manage")])
        await safe_edit(
            query,
            "اختر المستخدم الذي تريد حذفه:",
            keyboard=InlineKeyboardMarkup(rows),
        )

    elif data == "manage_list":
        if user_id != OWNER_ID:
            await safe_edit(query, "غير مصرح لك.")
            return
        users = list_allowed_users()
        if not users:
            text = "لا يوجد مستخدمون مصرح لهم."
        else:
            lines = "\n".join(f"• {uid}" for uid in users)
            text  = f"المستخدمون المصرح لهم:\n---------------------------------\n{lines}"
        await safe_edit(
            query, text,
            keyboard=InlineKeyboardMarkup([[InlineKeyboardButton("رجوع", callback_data="manage")]]),
        )

    elif data.startswith("mdel_"):
        if user_id != OWNER_ID:
            await safe_edit(query, "غير مصرح لك.")
            return
        try:
            target_id = int(data.split("_", 1)[1])
            remove_allowed_user(target_id)
            add_log(user_id, "remove_allowed", str(target_id))
            await safe_edit(
                query,
                f"تم حذف المستخدم {target_id} بنجاح.",
                keyboard=InlineKeyboardMarkup([
                    [InlineKeyboardButton("حذف مستخدم اخر", callback_data="manage_remove")],
                    [InlineKeyboardButton("رجوع",            callback_data="manage")],
                ]),
            )
        except Exception as e:
            await safe_edit(query, f"خطا في الحذف: {e}")

    elif data == "main":
        await start(update, context)


async def handle_text(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    user_id = update.effective_user.id
    text    = update.message.text.strip()
    state   = context.user_data.get("login_state")

    if state is None:
        return

    if state == MANAGE_ADD_USER:
        if user_id != OWNER_ID:
            context.user_data.pop("login_state", None)
            return
        if text.lstrip('+').isdigit():
            target_id = int(text.lstrip('+'))
            if target_id == OWNER_ID:
                await update.message.reply_text("المالك مضاف مسبقا.")
            else:
                add_allowed_user(target_id)
                add_log(user_id, "add_allowed", str(target_id))
                await update.message.reply_text(f"تم اضافة المستخدم {target_id} بنجاح.")
            context.user_data.pop("login_state", None)
            keyboard = InlineKeyboardMarkup([
                [InlineKeyboardButton("اضافة مستخدم",    callback_data="manage_add")],
                [InlineKeyboardButton("حذف مستخدم",      callback_data="manage_remove")],
                [InlineKeyboardButton("عرض المستخدمين",  callback_data="manage_list")],
                [InlineKeyboardButton("رجوع",             callback_data="main")],
            ])
            await update.message.reply_text("لوحة ادارة المستخدمين:", reply_markup=keyboard)
        else:
            await update.message.reply_text("الرجاء ارسال معرف المستخدم (ارقام فقط).\nمثال: 123456789")
        return

    if state == LOGIN_PHONE:
        phone  = text
        old_client = context.user_data.get("temp_client")
        if old_client:
            try:
                await old_client.disconnect()
            except Exception:
                pass
        client = _make_client()
        context.user_data.update(phone=phone, temp_client=client, login_state=LOGIN_CODE)
        try:
            await client.connect()
            await client.send_code_request(phone)
            await update.message.reply_text(
                "تم ارسال رمز التحقق.\n"
                "لتجنب حماية تيليغرام، ارسل الرمز مع نقاط.\n"
                "مثال: 1.2.3.4.5"
            )
        except Exception as e:
            await update.message.reply_text(f"خطا في ارسال الرمز: {e}")
            try:
                await client.disconnect()
            except Exception:
                pass
            context.user_data.pop("login_state", None)
            context.user_data.pop("phone",       None)
            context.user_data.pop("temp_client", None)

    elif state == LOGIN_CODE:
        code        = re.sub(r"\.", "", text)
        phone       = context.user_data.get("phone")
        temp_client = context.user_data.get("temp_client")
        if not temp_client:
            await update.message.reply_text("انتهت الجلسة، ابدا من جديد.")
            context.user_data.pop("login_state", None)
            return
        try:
            await temp_client.sign_in(phone, code)
            session_string = temp_client.session.save()
            set_user(user_id, phone, session_string)
            start_monitoring(user_id, session_string)
            await update.message.reply_text("تم تسجيل الدخول. المراقبة تعمل 24/7.")
            await temp_client.disconnect()
            for k in ("login_state", "phone", "temp_client"):
                context.user_data.pop(k, None)
            await start(update, context)

        except SessionPasswordNeededError:
            context.user_data["login_state"] = LOGIN_PASSWORD
            await update.message.reply_text("الحساب محمي بالتحقق بخطوتين. ارسل كلمة المرور:")

        except Exception as e:
            await update.message.reply_text(f"فشل تسجيل الدخول: {e}")
            try:
                await temp_client.disconnect()
            except Exception:
                pass
            for k in ("login_state", "phone", "temp_client"):
                context.user_data.pop(k, None)

    elif state == LOGIN_PASSWORD:
        temp_client = context.user_data.get("temp_client")
        if not temp_client:
            await update.message.reply_text("انتهت الجلسة، ابدا من جديد.")
            context.user_data.pop("login_state", None)
            return
        try:
            await temp_client.sign_in(password=text)
            session_string = temp_client.session.save()
            set_user(user_id, context.user_data["phone"], session_string)
            start_monitoring(user_id, session_string)
            await update.message.reply_text("تم تسجيل الدخول. المراقبة تعمل 24/7.")
            await temp_client.disconnect()
            for k in ("login_state", "phone", "temp_client"):
                context.user_data.pop(k, None)
            await start(update, context)

        except Exception as e:
            await update.message.reply_text(f"كلمة المرور غير صحيحة: {e}")

async def restore_monitors() -> None:
    """Restore monitoring sessions on bot restart."""
    for uid_str, ud in load_data()["users"].items():
        ss = ud.get("session_string")
        if not ss:
            continue
        user_id = int(uid_str)
        start_monitoring(user_id, ss)
        print(f"[{user_id}] Monitor restored (24/7)")

async def _cleanup() -> None:
    """Gracefully stop all monitors and disconnect all clients."""
    print("[Bot] Shutting down — cancelling monitor tasks...")
    for task in list(monitor_tasks.values()):
        if not task.done():
            task.cancel()
    if monitor_tasks:
        await asyncio.gather(*monitor_tasks.values(), return_exceptions=True)
    for client in list(active_monitors.values()):
        try:
            await client.disconnect()
        except Exception:
            pass
    print("[Bot] All monitors stopped.")

async def run() -> None:
    add_allowed_user(OWNER_ID)

    app.add_handler(CommandHandler("start", start))
    app.add_handler(CallbackQueryHandler(button_callback))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_text))

    async with app:
        await app.start()
        print("[Bot] Protection bot is running...")

        await restore_monitors()
        await app.updater.start_polling(
            allowed_updates=Update.ALL_TYPES,
            drop_pending_updates=True,
        )

        print("[Bot] Polling started. Press Ctrl+C to stop.")

        try:
            await asyncio.Event().wait()
        finally:
            print("[Bot] Stopping...")
            try:
                await app.updater.stop()
            except Exception:
                pass
            try:
                await app.stop()
            except Exception:
                pass
            await _cleanup()

if __name__ == "__main__":
    try:
        asyncio.run(run())
    except KeyboardInterrupt:
        print("[Bot] Interrupted by user (KeyboardInterrupt).")
    except Exception as e:
        print(f"[Bot] Fatal error: {e}")
        sys.exit(1)
