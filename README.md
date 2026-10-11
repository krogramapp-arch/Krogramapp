# KroGram

تطبيق iOS مستقل وغير رسمي للمراسلة عبر تيليجرام، مبني بـ Swift وSwiftUI وTDLib.

## تجهيز المستودع

توجد ملفات التطبيق والاختبارات مباشرةً في مجلد `KroGram/`، وملف `codemagic.yaml` في جذر المستودع. يقرأ Codemagic المشروع من `KroGram/project.yml` دون الحاجة إلى فك أي أرشيف أثناء البناء. لا ترفع مفاتيح أو ملفات توقيع سرية إلى المستودع.

يتضمن المشروع مجلدي `KroGram/KroGram/` لمصادر التطبيق و`KroGram/KroGramTests/` للاختبارات.

## البناء على Codemagic

1. أضف مستودع GitHub إلى Codemagic واختر إعداد `Other / codemagic.yaml`.
2. استخدم Workflow `KroGram - Build & Test` للتحقق من البناء والاختبارات على محاكي iOS.
3. استخدم `KroGram - Unsigned IPA` لإنتاج IPA غير موقّع للتنزيل والاختبار بأدوات توقيع خارجية.
4. لتثبيت التطبيق على أجهزة مسجلة، استخدم `KroGram - Ad Hoc IPA`. يتطلب ذلك عضوية Apple Developer، وشهادة وملف provisioning من نوع Ad Hoc يتضمن المعرّف `com.krogram.app` والأجهزة المسجلة، وإعداد التوقيع في Codemagic.

Workflow الاختبارات يعمل تلقائيًا عند الدفع إلى فرع `main`. قد يستغرق أول بناء وقتًا أطول بسبب تنزيل XcodeGen وحزمة `TDLibFramework`.

## التطبيق

- عند أول تشغيل، تظهر شاشة لإدخال `api_id` و`api_hash` قبل تسجيل الدخول. احصل عليهما من `my.telegram.org`؛ تُحفظ القيم في Keychain على الجهاز فقط. يمكن اختيار وضع العرض التجريبي من الشاشة نفسها.
- وضع تجريبي متاح دون تسجيل دخول.
- مجموعة أوامر KroGram Commander آمنة ومعاد تنفيذها أصليًا في Swift، قابلة للتفعيل والتعطيل من الإعدادات؛ تشمل الحاسبة وأدوات النص ومعلومات المحادثة وإجراءاتها وبعض الألعاب المحلية، وليست تشغيلًا لكل ميزات userbot الأصلية. تنزيل الفيديوهات غير مدعوم حاليًا.
- اللغتان العربية والإنجليزية.

التفاصيل المعمارية وحالة الميزات في [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## تغيير معرّف التطبيق

عدّل `PRODUCT_BUNDLE_IDENTIFIER` في `KroGram/project.yml` و`bundle_identifier` في Workflow التوقيع معًا قبل إعداد التوقيع. يجب أن يطابق المعرّف ملف provisioning في Apple Developer.
