# KroChat

عميل مراسلة iOS مستقل وغير رسمي مبني بـ Swift وSwiftUI.
**المرحلة 1: واجهات ببيانات تجريبية. لا اتصال بتيليجرام بعد.**

التفاصيل المعمارية وجدول ما يعمل وما لا يعمل: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)

> لم يُبنَ هذا المشروع ولم تُشغَّل اختباراته بعد. أول بناء على Codemagic هو الاختبار الحقيقي الأول، وقد تظهر أخطاء ترجمة تُصلَح بعد قراءة سجل البناء.

## الخطوة 1: رفع الملفات إلى GitHub من الآيفون

**الطريقة أ: تطبيق Working Copy (الأسهل للمجلدات)**
1. افتح ملف ZIP في تطبيق "الملفات" واضغط عليه لفك الضغط.
2. من Working Copy أنشئ مستودعًا جديدًا (Create repository) ثم اربطه بمستودع فارغ أنشأته في github.com.
3. انسخ محتويات مجلد `KroChat` المفكوك إلى المستودع (من زر الإضافة > Link/Import files)، ثم Commit ثم Push.
4. تحقق من سياسة التطبيق وحدوده المجانية بنفسك قبل الاعتماد عليه، فلم أتحقق منها.

**الطريقة ب: Safari فقط (بلا تطبيقات)**
1. في github.com أنشئ مستودعًا جديدًا (اجعله **Private**).
2. اضغط Add file ← Create new file.
3. في خانة الاسم اكتب المسار كاملًا مثل `KroChat/App/KroChatApp.swift` (كتابة `/` تنشئ المجلد تلقائيًا).
4. الصق محتوى الملف ثم Commit changes. كرّر لكل ملف (نحو 30 ملفًا).
5. ملف الأيقونة `icon-1024.png` ثنائي، فارفعه عبر Add file ← Upload files إلى المسار `KroChat/Resources/Assets.xcassets/AppIcon.appiconset/`.

## الخطوة 2: البناء على Codemagic

1. ادخل codemagic.io بحساب GitHub، ثم Add application واختر المستودع.
2. اختر نوع المشروع "Other / codemagic.yaml" فيقرأ `codemagic.yaml` تلقائيًا.
3. شغّل Workflow يدويًا (Start new build). يوجد Workflow لبناء IPA غير موقّع، وWorkflow آخر لإنتاج IPA موقّع يمكن تثبيته على أجهزة مسجّلة.

## الحصول على IPA للتثبيت على الآيفون

Workflow باسم `KroChat - Unsigned IPA` ينتج ملف IPA غير موقّع، ولا يمكن تثبيته مباشرة على الآيفون. للتثبيت على `ksgin` و`esgin` استخدم `KroChat - Ad Hoc IPA`، الذي يبني ملفًا موقّعًا. يتطلب ذلك:

1. عضوية Apple Developer مدفوعة، وربط App Store Connect بحساب Codemagic عبر API key.
2. تسجيل UDID لكل من `ksgin` و`esgin` في حساب Apple Developer، ثم إنشاء/تحديث Ad Hoc provisioning profile للتطبيق `com.krochat.app` يتضمن الجهازين وإضافته إلى إعدادات التوقيع في Codemagic.
3. بعد حفظ `codemagic.yaml` على الفرع الذي يتتبعه التطبيق، افتح التطبيق في Codemagic واختر `KroChat - Ad Hoc IPA` من `Start new build`. نزّل ملف `.ipa` من Artifacts عند نجاح البناء.

إذا لم يظهر Workflow، تحقق من أن التطبيق في Codemagic مربوط بالمستودع والفرع الصحيحين وأن إعداد مصدر الإعداد هو `codemagic.yaml` في جذر المستودع، ثم أعد تحميل صفحة التطبيق.

ملاحظات:
- الخطة المجانية في Codemagic لها حد دقائق شهري؛ راجعه في موقعهم.
- TestFlight ليس مضبوطًا بعد (المرحلة 4)، ويحتاج حساب Apple Developer مدفوعًا.

## تغيير اسم الحزمة

`PRODUCT_BUNDLE_IDENTIFIER` في `project.yml` هو `com.krochat.app`. غيّره إلى معرّف يخصك قبل أي توقيع.

## المراحل

1. **(هذه)** الهيكل، نظام التصميم، الشاشات ببيانات تجريبية.
2. Telegram API وتسجيل الدخول الآمن وربط المحادثات الحقيقية.
3. حسابات متعددة، بحث متقدم، خصوصية محلية، وسائط.
4. اختبارات واجهة، مراجعة أمان وتراخيص، توقيع، TestFlight.
