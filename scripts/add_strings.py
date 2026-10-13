#!/usr/bin/env python3
"""Adds wxShot-specific strings to every Resources/<lang>.lproj/Localizable.strings.
Idempotent: existing keys are left untouched. Run from the repo root: python3 scripts/add_strings.py"""
import re, pathlib

LANGS = ["en", "zh-Hans", "zh-Hant", "ja", "ko", "fr", "ru", "vi"]

S = {
 "wxSettingsWindowTitle": {
  "en": "wxShot Settings", "zh-Hans": "wxShot 设置", "zh-Hant": "wxShot 設定", "ja": "wxShot 設定", "ko": "wxShot 설정", "fr": "Réglages de wxShot", "ru": "Настройки wxShot", "vi": "Cài đặt wxShot"},
 "wxSectionShortcut": {
  "en": "Screenshot shortcut", "zh-Hans": "截图快捷键", "zh-Hant": "截圖快速鍵", "ja": "スクリーンショットのショートカット", "ko": "스크린샷 단축키", "fr": "Raccourci de capture", "ru": "Сочетание клавиш", "vi": "Phím tắt chụp màn hình"},
 "wxShortcutDefaultNote": {
  "en": "The default ⌥A is the same as WeChat's screenshot shortcut, so your habits carry over", "zh-Hans": "默认 ⌥A，与微信截图习惯一致，无需重新适应", "zh-Hant": "預設 ⌥A，與微信截圖習慣一致，無需重新適應", "ja": "既定の ⌥A は WeChat のスクリーンショットと同じなので、操作感はそのままです", "ko": "기본값 ⌥A 는 WeChat 스크린샷과 같아서 손에 익은 그대로 쓸 수 있습니다", "fr": "⌥A par défaut, comme la capture de WeChat : vos habitudes restent les mêmes", "ru": "По умолчанию ⌥A, как в скриншоте WeChat — привычки сохраняются", "vi": "Mặc định ⌥A, giống phím chụp của WeChat nên bạn không cần làm quen lại"},
 "wxSectionWeChat": {
  "en": "When WeChat is open", "zh-Hans": "微信打开时", "zh-Hant": "微信開啟時", "ja": "WeChat が起動しているとき", "ko": "WeChat 이 실행 중일 때", "fr": "Quand WeChat est ouvert", "ru": "Когда открыт WeChat", "vi": "Khi WeChat đang mở"},
 "wxPolicyAuto": {
  "en": "Automatic: WeChat takes over once it is signed in", "zh-Hans": "自动：微信登录后交给微信，未登录时用 wxShot", "zh-Hant": "自動：微信登入後交給微信，未登入時用 wxShot", "ja": "自動：WeChat にログインしたら WeChat に任せる", "ko": "자동: WeChat 에 로그인하면 WeChat 이 처리", "fr": "Automatique : WeChat prend le relais une fois connecté", "ru": "Авто: после входа в WeChat снимает он", "vi": "Tự động: WeChat đảm nhận khi đã đăng nhập"},
 "wxPolicyAlways": {
  "en": "Always use wxShot", "zh-Hans": "始终使用 wxShot 截图", "zh-Hant": "一律使用 wxShot 截圖", "ja": "常に wxShot を使う", "ko": "항상 wxShot 사용", "fr": "Toujours utiliser wxShot", "ru": "Всегда использовать wxShot", "vi": "Luôn dùng wxShot"},
 "wxPolicyYield": {
  "en": "Let WeChat handle it whenever it is running", "zh-Hans": "微信运行时一律交给微信", "zh-Hant": "微信執行時一律交給微信", "ja": "WeChat が起動中は常に WeChat に任せる", "ko": "WeChat 이 실행 중이면 항상 WeChat 에 맡기기", "fr": "Laisser WeChat gérer dès qu'il est lancé", "ru": "Пока запущен WeChat, снимает он", "vi": "Nhường cho WeChat mỗi khi nó đang chạy"},
 "wxPolicyHint": {
  "en": "If both apps use the same shortcut and wxShot is set to always capture, change one of them to avoid two screenshots at once", "zh-Hans": "若选择始终使用 wxShot，请把微信或 wxShot 的快捷键改成不同的，避免一次按键弹出两个截图", "zh-Hant": "若選擇一律使用 wxShot，請將微信或 wxShot 的快速鍵改成不同的，避免一次按鍵彈出兩個截圖", "ja": "常に wxShot を使う場合は、同時に二つ起動しないようどちらかのショートカットを変えてください", "ko": "항상 wxShot 을 쓴다면 두 앱의 단축키를 다르게 바꿔 한 번에 두 개가 뜨지 않게 하세요", "fr": "Si wxShot capture toujours, changez l'un des raccourcis pour éviter deux captures en même temps", "ru": "Если выбрано «всегда wxShot», измените сочетание в одном из приложений, чтобы не открывались два скриншота", "vi": "Nếu chọn luôn dùng wxShot, hãy đổi phím tắt của một trong hai để tránh bật hai lần chụp cùng lúc"},
 "wxWeChatStatusNotRunning": {
  "en": "WeChat is not running", "zh-Hans": "微信未运行", "zh-Hant": "微信未執行", "ja": "WeChat は起動していません", "ko": "WeChat 이 실행 중이 아닙니다", "fr": "WeChat n'est pas lancé", "ru": "WeChat не запущен", "vi": "WeChat chưa chạy"},
 "wxWeChatStatusLoginScreen": {
  "en": "WeChat is open but not signed in", "zh-Hans": "微信已打开但未登录", "zh-Hant": "微信已開啟但未登入", "ja": "WeChat は起動中ですがログインしていません", "ko": "WeChat 이 열려 있지만 로그인하지 않았습니다", "fr": "WeChat est ouvert mais non connecté", "ru": "WeChat открыт, но вход не выполнен", "vi": "WeChat đang mở nhưng chưa đăng nhập"},
 "wxWeChatStatusLoggedIn": {
  "en": "WeChat is signed in", "zh-Hans": "微信已登录", "zh-Hant": "微信已登入", "ja": "WeChat にログイン済みです", "ko": "WeChat 에 로그인되어 있습니다", "fr": "WeChat est connecté", "ru": "В WeChat выполнен вход", "vi": "WeChat đã đăng nhập"},
 "wxShortcutOwner": {
  "en": "Right now the shortcut is handled by %@", "zh-Hans": "当前快捷键由 %@ 响应", "zh-Hant": "目前快速鍵由 %@ 回應", "ja": "現在このショートカットは %@ が処理します", "ko": "현재 이 단축키는 %@ 이(가) 처리합니다", "fr": "Pour l'instant, le raccourci est géré par %@", "ru": "Сейчас сочетание обрабатывает %@", "vi": "Hiện phím tắt do %@ xử lý"},
 "wxOwnerWeChat": {
  "en": "WeChat", "zh-Hans": "微信", "zh-Hant": "微信", "ja": "WeChat", "ko": "WeChat", "fr": "WeChat", "ru": "WeChat", "vi": "WeChat"},
 "wxSectionGeneral": {
  "en": "General", "zh-Hans": "通用", "zh-Hant": "一般", "ja": "一般", "ko": "일반", "fr": "Général", "ru": "Основные", "vi": "Chung"},
 "wxTelemetryToggle": {
  "en": "Send anonymous \"still in use\" statistics", "zh-Hans": "发送匿名使用统计（仅存活信息）", "zh-Hant": "傳送匿名使用統計（僅存活資訊）", "ja": "匿名の利用状況を送信する（稼働情報のみ）", "ko": "익명 사용 통계 보내기 (사용 여부만)", "fr": "Envoyer des statistiques anonymes d'utilisation", "ru": "Отправлять анонимную статистику использования", "vi": "Gửi thống kê ẩn danh (chỉ cho biết còn dùng)"},
 "wxTelemetryHint": {
  "en": "Only an install id, version, system and language, a few times in the first month. Never screenshots, text or files", "zh-Hans": "仅包含随机安装编号、版本、系统和语言，首月只发几次。绝不上传截图、文字或文件", "zh-Hant": "僅包含隨機安裝編號、版本、系統和語言，首月只發幾次。絕不上傳截圖、文字或檔案", "ja": "ランダムなインストール ID、バージョン、OS、言語のみを最初の一か月に数回送信します。スクリーンショットや文字、ファイルは送りません", "ko": "임의의 설치 ID, 버전, 시스템, 언어만 첫 달에 몇 번 보냅니다. 스크린샷, 텍스트, 파일은 절대 보내지 않습니다", "fr": "Seulement un identifiant d'installation, la version, le système et la langue, quelques fois le premier mois. Jamais de captures, de texte ni de fichiers", "ru": "Только случайный ID установки, версия, система и язык — несколько раз за первый месяц. Никаких скриншотов, текста и файлов", "vi": "Chỉ gồm mã cài đặt ngẫu nhiên, phiên bản, hệ điều hành và ngôn ngữ, vài lần trong tháng đầu. Không bao giờ gửi ảnh, văn bản hay tệp"},
 "wxPermissionStatusGranted": {
  "en": "Screen recording is allowed", "zh-Hans": "已允许屏幕录制", "zh-Hant": "已允許螢幕錄製", "ja": "画面収録は許可されています", "ko": "화면 기록이 허용되었습니다", "fr": "L'enregistrement d'écran est autorisé", "ru": "Запись экрана разрешена", "vi": "Đã cho phép ghi màn hình"},
 "wxPermissionStatusMissing": {
  "en": "Screen recording is not allowed yet", "zh-Hans": "尚未允许屏幕录制", "zh-Hant": "尚未允許螢幕錄製", "ja": "画面収録がまだ許可されていません", "ko": "화면 기록이 아직 허용되지 않았습니다", "fr": "L'enregistrement d'écran n'est pas encore autorisé", "ru": "Запись экрана ещё не разрешена", "vi": "Chưa cho phép ghi màn hình"},
 "wxOpenSystemSettings": {
  "en": "Open System Settings", "zh-Hans": "打开系统设置", "zh-Hant": "打開系統設定", "ja": "システム設定を開く", "ko": "시스템 설정 열기", "fr": "Ouvrir Réglages Système", "ru": "Открыть Системные настройки", "vi": "Mở Cài đặt hệ thống"},
 "wxWelcomeTitle": {
  "en": "Welcome to wxShot", "zh-Hans": "欢迎使用 wxShot", "zh-Hant": "歡迎使用 wxShot", "ja": "wxShot へようこそ", "ko": "wxShot 에 오신 것을 환영합니다", "fr": "Bienvenue dans wxShot", "ru": "Добро пожаловать в wxShot", "vi": "Chào mừng đến với wxShot"},
 "wxWelcomeBody": {
  "en": "The WeChat-style screenshot that works whether or not WeChat is signed in. It runs quietly in the background and answers one shortcut", "zh-Hans": "微信同款截图体验，不用登录微信也能用。静静待在后台，只响应一个快捷键", "zh-Hant": "微信同款截圖體驗，不用登入微信也能用。靜靜待在背景，只回應一個快速鍵", "ja": "WeChat と同じ使い心地のスクリーンショット。ログインしていなくても使えます。バックグラウンドで静かに待機し、ひとつのショートカットだけに反応します", "ko": "WeChat 로그인 여부와 상관없이 쓰는 WeChat 스타일 스크린샷. 백그라운드에서 조용히 대기하며 단축키 하나에만 반응합니다", "fr": "La capture façon WeChat, qui marche connecté ou non. Elle reste discrète en arrière-plan et répond à un seul raccourci", "ru": "Скриншоты как в WeChat — с входом в WeChat и без него. Тихо работает в фоне и отвечает на одно сочетание клавиш", "vi": "Chụp màn hình kiểu WeChat, dùng được cả khi chưa đăng nhập WeChat. Chạy ngầm yên lặng và chỉ phản hồi một phím tắt"},
 "wxStepPermission": {
  "en": "1  Allow screen recording", "zh-Hans": "1  允许屏幕录制", "zh-Hant": "1  允許螢幕錄製", "ja": "1  画面収録を許可", "ko": "1  화면 기록 허용", "fr": "1  Autoriser l'enregistrement d'écran", "ru": "1  Разрешить запись экрана", "vi": "1  Cho phép ghi màn hình"},
 "wxStepPermissionNote": {
  "en": "macOS requires this for every screenshot app. wxShot only looks at the area you select and never sends it anywhere", "zh-Hans": "这是 macOS 对所有截图软件的要求。wxShot 只处理你框选的区域，不会上传任何画面", "zh-Hant": "這是 macOS 對所有截圖軟體的要求。wxShot 只處理你框選的區域，不會上傳任何畫面", "ja": "これはすべてのスクリーンショットアプリに対する macOS の要件です。wxShot は選択した範囲だけを扱い、どこにも送信しません", "ko": "모든 스크린샷 앱에 필요한 macOS 요구사항입니다. wxShot 은 선택한 영역만 처리하며 어디에도 전송하지 않습니다", "fr": "macOS l'exige pour toute application de capture. wxShot ne traite que la zone choisie et ne l'envoie nulle part", "ru": "Этого требует macOS от любых приложений для скриншотов. wxShot обрабатывает только выбранную область и никуда её не отправляет", "vi": "macOS yêu cầu điều này với mọi ứng dụng chụp màn hình. wxShot chỉ xử lý vùng bạn chọn và không gửi đi đâu"},
 "wxStepShortcut": {
  "en": "2  Press %@ anywhere to capture", "zh-Hans": "2  在任何界面按 %@ 即可截图", "zh-Hant": "2  在任何介面按 %@ 即可截圖", "ja": "2  どこでも %@ を押して撮影", "ko": "2  어디서든 %@ 를 눌러 캡처", "fr": "2  Appuyez sur %@ n'importe où pour capturer", "ru": "2  Нажмите %@ где угодно, чтобы сделать снимок", "vi": "2  Nhấn %@ ở bất kỳ đâu để chụp"},
 "wxStepShortcutNote": {
  "en": "Drag to select, double-click or press Return to copy, press Esc to cancel. Open wxShot again any time to change settings", "zh-Hans": "拖动框选，双击或回车复制，Esc 取消。随时再次打开 wxShot 即可修改设置", "zh-Hant": "拖曳框選，雙擊或按 Return 複製，Esc 取消。隨時再次打開 wxShot 即可修改設定", "ja": "ドラッグで範囲選択、ダブルクリックか Return でコピー、Esc で取消。設定は wxShot をもう一度開けばいつでも変更できます", "ko": "드래그로 선택, 더블클릭이나 Return 으로 복사, Esc 로 취소. 설정은 wxShot 을 다시 열면 언제든 바꿀 수 있습니다", "fr": "Glissez pour sélectionner, double-clic ou Retour pour copier, Échap pour annuler. Rouvrez wxShot pour modifier les réglages", "ru": "Выделите область, двойной щелчок или Return копирует, Esc отменяет. Откройте wxShot снова, чтобы изменить настройки", "vi": "Kéo để chọn, nhấp đúp hoặc Return để sao chép, Esc để hủy. Mở lại wxShot bất cứ lúc nào để đổi cài đặt"},
 "wxStartButton": {
  "en": "Start Using wxShot", "zh-Hans": "开始使用", "zh-Hant": "開始使用", "ja": "使い始める", "ko": "시작하기", "fr": "Commencer", "ru": "Начать", "vi": "Bắt đầu dùng"},
 "wxLaterButton": {
  "en": "Later", "zh-Hans": "稍后", "zh-Hant": "稍後", "ja": "あとで", "ko": "나중에", "fr": "Plus tard", "ru": "Позже", "vi": "Để sau"},
 "wxAboutWebsite": {
  "en": "Website", "zh-Hans": "官网", "zh-Hant": "官網", "ja": "公式サイト", "ko": "웹사이트", "fr": "Site web", "ru": "Сайт", "vi": "Trang web"},
 "wxAboutSource": {
  "en": "Source code (MIT)", "zh-Hans": "开源代码（MIT）", "zh-Hant": "開源程式碼（MIT）", "ja": "ソースコード（MIT）", "ko": "소스 코드 (MIT)", "fr": "Code source (MIT)", "ru": "Исходный код (MIT)", "vi": "Mã nguồn (MIT)"},
 "wxStarOnGitHub": {
  "en": "Star wxShot on GitHub", "zh-Hans": "在 GitHub 上给 wxShot 点个 Star", "zh-Hant": "在 GitHub 上給 wxShot 點個 Star", "ja": "GitHub で wxShot にスターを付ける", "ko": "GitHub 에서 wxShot 에 별 주기", "fr": "Mettre une étoile à wxShot sur GitHub", "ru": "Поставить звезду wxShot на GitHub", "vi": "Gắn sao wxShot trên GitHub"},
 "wxConfirmDiscard": {
  "en": "Press again to exit — your edits will be lost", "zh-Hans": "再按一次退出，当前标注将丢失", "zh-Hant": "再按一次退出，目前標註將遺失", "ja": "もう一度押すと終了します（編集内容は失われます）", "ko": "한 번 더 누르면 종료됩니다 (편집 내용이 사라집니다)", "fr": "Appuyez à nouveau pour quitter — vos modifications seront perdues", "ru": "Нажмите ещё раз, чтобы выйти — правки будут потеряны", "vi": "Nhấn lần nữa để thoát — các chỉnh sửa sẽ bị mất"},
 "wxTipSettings": {
  "en": "Settings", "zh-Hans": "设置", "zh-Hant": "設定", "ja": "設定", "ko": "설정", "fr": "Réglages", "ru": "Настройки", "vi": "Cài đặt"},
 "wxSectionFeedback": {
  "en": "Feedback", "zh-Hans": "用户反馈", "zh-Hant": "使用者回饋", "ja": "フィードバック", "ko": "피드백", "fr": "Commentaires", "ru": "Обратная связь", "vi": "Phản hồi"},
 "wxFeedbackHint": {
  "en": "Missing a feature, found a bug, or have an idea? Tell us — wxShot keeps improving from your feedback.", "zh-Hans": "想要的功能、遇到的问题、好点子都可以告诉我们，wxShot 会根据反馈持续优化。", "zh-Hant": "想要的功能、遇到的問題、好點子都可以告訴我們，wxShot 會根據回饋持續優化。", "ja": "欲しい機能、不具合、アイデアなど何でもお寄せください。wxShot はフィードバックをもとに改善を続けます。", "ko": "원하는 기능, 문제점, 아이디어를 알려 주세요. wxShot 은 피드백을 바탕으로 계속 개선됩니다.", "fr": "Une fonction manquante, un bug, une idée ? Dites-le-nous : wxShot s'améliore grâce à vos retours.", "ru": "Нужна функция, нашли ошибку или есть идея? Напишите нам — wxShot развивается благодаря вашим отзывам.", "vi": "Thiếu tính năng, gặp lỗi hay có ý tưởng? Hãy cho chúng tôi biết — wxShot luôn được cải thiện nhờ phản hồi của bạn."},
 "wxFeedbackButton": {
  "en": "Send Feedback…", "zh-Hans": "提交反馈…", "zh-Hant": "提交回饋…", "ja": "フィードバックを送る…", "ko": "피드백 보내기…", "fr": "Envoyer un commentaire…", "ru": "Отправить отзыв…", "vi": "Gửi phản hồi…"},
 "wxFeedbackTitle": {
  "en": "Send feedback", "zh-Hans": "提交反馈", "zh-Hant": "提交回饋", "ja": "フィードバックを送る", "ko": "피드백 보내기", "fr": "Envoyer un commentaire", "ru": "Отправить отзыв", "vi": "Gửi phản hồi"},
 "wxFeedbackInfo": {
  "en": "Describe the feature you want or the problem you ran into. Your mail app opens with this text filled in; the app and macOS versions are added.", "zh-Hans": "请描述你想要的功能或遇到的问题。点击发送会打开邮件应用并填好内容，同时附上软件与系统版本。", "zh-Hant": "請描述你想要的功能或遇到的問題。按下傳送會開啟郵件 App 並填好內容，同時附上軟體與系統版本。", "ja": "欲しい機能や困っていることを書いてください。メールアプリが開き、本文が入力され、アプリと macOS のバージョンが付きます。", "ko": "원하는 기능이나 겪은 문제를 적어 주세요. 메일 앱이 열리며 내용이 채워지고 앱·macOS 버전이 함께 들어갑니다.", "fr": "Décrivez la fonction souhaitée ou le problème rencontré. Votre application Mail s'ouvre avec le texte, plus les versions de l'app et de macOS.", "ru": "Опишите нужную функцию или проблему. Откроется почтовое приложение с этим текстом и версиями приложения и macOS.", "vi": "Hãy mô tả tính năng bạn muốn hoặc sự cố gặp phải. Ứng dụng thư sẽ mở với nội dung này kèm phiên bản ứng dụng và macOS."},
 "wxFeedbackSend": {
  "en": "Send", "zh-Hans": "发送", "zh-Hant": "傳送", "ja": "送信", "ko": "보내기", "fr": "Envoyer", "ru": "Отправить", "vi": "Gửi"},
 "wxFeedbackGitHub": {
  "en": "GitHub Issues", "zh-Hans": "GitHub 反馈区", "zh-Hant": "GitHub Issues", "ja": "GitHub Issues", "ko": "GitHub Issues", "fr": "GitHub Issues", "ru": "GitHub Issues", "vi": "GitHub Issues"},
 "wxTipShare": {
  "en": "Share", "zh-Hans": "分享", "zh-Hant": "分享", "ja": "共有", "ko": "공유", "fr": "Partager", "ru": "Поделиться", "vi": "Chia sẻ"},
 "wxTipMore": {
  "en": "More", "zh-Hans": "更多", "zh-Hant": "更多", "ja": "その他", "ko": "더보기", "fr": "Plus", "ru": "Ещё", "vi": "Thêm"},
 "wxTranslateHeader": {
  "en": "Translation", "zh-Hans": "翻译", "zh-Hant": "翻譯", "ja": "翻訳", "ko": "번역", "fr": "Traduction", "ru": "Перевод", "vi": "Bản dịch"},
 "wxTranslating": {
  "en": "Translating…", "zh-Hans": "翻译中…", "zh-Hant": "翻譯中…", "ja": "翻訳中…", "ko": "번역 중…", "fr": "Traduction…", "ru": "Перевод…", "vi": "Đang dịch…"},
 "wxTranslateUnsupported": {
  "en": "Translation needs macOS 15 or later", "zh-Hans": "翻译功能需要 macOS 15 或更高版本", "zh-Hant": "翻譯功能需要 macOS 15 或更新版本", "ja": "翻訳には macOS 15 以降が必要です", "ko": "번역에는 macOS 15 이상이 필요합니다", "fr": "La traduction nécessite macOS 15 ou ultérieur", "ru": "Для перевода нужна macOS 15 или новее", "vi": "Dịch cần macOS 15 trở lên"},
 "wxTranslateFailed": {
  "en": "Translation failed. Make sure the language pack is downloaded in System Settings › General › Language & Region › Translation Languages", "zh-Hans": "翻译失败。请在 系统设置 › 通用 › 语言与地区 › 翻译语言 中下载对应语言", "zh-Hant": "翻譯失敗。請在 系統設定 › 一般 › 語言與地區 › 翻譯語言 中下載對應語言", "ja": "翻訳に失敗しました。システム設定 › 一般 › 言語と地域 › 翻訳言語 で言語をダウンロードしてください", "ko": "번역에 실패했습니다. 시스템 설정 › 일반 › 언어 및 지역 › 번역 언어 에서 언어를 내려받으세요", "fr": "Échec de la traduction. Téléchargez la langue dans Réglages Système › Général › Langue et région › Langues de traduction", "ru": "Не удалось перевести. Загрузите язык в Системные настройки › Основные › Язык и регион › Языки перевода", "vi": "Dịch thất bại. Hãy tải gói ngôn ngữ trong Cài đặt hệ thống › Cài đặt chung › Ngôn ngữ & Vùng › Ngôn ngữ dịch"},
 "wxLensCopyHint": {
  "en": "Press ⌘+C to copy the color", "zh-Hans": "按 ⌘+C 复制色值", "zh-Hant": "按 ⌘+C 複製色值", "ja": "⌘+C で色をコピー", "ko": "⌘+C 로 색상 복사", "fr": "⌘+C pour copier la couleur", "ru": "⌘+C — копировать цвет", "vi": "Nhấn ⌘+C để sao chép màu"},
 "wxUpdateRequiredBody": {
  "en": "This version is no longer supported. Please download the latest version to keep using wxShot.", "zh-Hans": "此版本已不再支持，请下载最新版本后继续使用 wxShot。", "zh-Hant": "此版本已不再支援，請下載最新版本後繼續使用 wxShot。", "ja": "このバージョンはサポート終了です。wxShot を使い続けるには最新版をダウンロードしてください。", "ko": "이 버전은 더 이상 지원되지 않습니다. wxShot 을 계속 쓰려면 최신 버전을 내려받으세요.", "fr": "Cette version n'est plus prise en charge. Téléchargez la dernière version pour continuer à utiliser wxShot.", "ru": "Эта версия больше не поддерживается. Скачайте последнюю версию, чтобы продолжить пользоваться wxShot.", "vi": "Phiên bản này không còn được hỗ trợ. Vui lòng tải phiên bản mới nhất để tiếp tục dùng wxShot."},
}

root = pathlib.Path(__file__).resolve().parent.parent
for lang in LANGS:
    path = root / "Resources" / f"{lang}.lproj" / "Localizable.strings"
    text = path.read_text(encoding="utf-8")
    existing = set(re.findall(r'^"([^"]+)"\s*=', text, flags=re.M))
    add = []
    for key, vals in S.items():
        if key in existing:
            continue
        value = vals[lang].replace('"', '\\"')
        add.append(f'"{key}" = "{value}";')
    if add:
        text = text.rstrip("\n") + "\n\n/* wxShot */\n" + "\n".join(add) + "\n"
    path.write_text(text, encoding="utf-8")
    print(lang, "added", len(add))
