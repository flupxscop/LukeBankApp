# LuxeBank — Software Specification

| รายการ | รายละเอียด |
|---|---|
| เวอร์ชันเอกสาร | 0.4 (Draft) |
| วันที่ | 2026-10-11 |
| ขอบเขต | iOS App (SwiftUI) + Backend API (Spring Boot / Kotlin) |
| สถานะ | ข้อตกลงหลักยืนยันแล้ว ดูหัวข้อ [12. Decision Log](#12-decision-log) |

---

## 1. ภาพรวม

LuxeBank เป็นแอปธนาคารบน iOS สำหรับลูกค้ากลุ่มพรีเมียม เน้นหน้าตาหรูหรา (ธีมมืด โทนทอง) ใช้งานง่าย และปลอดภัย

เวอร์ชันนี้มีเป้าหมายเปลี่ยนแอปจาก **UI prototype ที่ใช้ mock data** ให้เป็น **แอปเต็มรูปแบบที่ทำงานกับ backend จริง** โดยมี 4 กลุ่มฟีเจอร์หลัก

1. เข้าสู่ระบบ + PIN / Face ID
2. โอนเงิน / จ่ายบิล
3. จัดการบัตร
4. ประวัติรายการ + โปรไฟล์

### 1.1 สถานะปัจจุบันของโค้ด (As-is)

| ส่วน | สถานะ |
|---|---|
| `DashboardView` | ทำเสร็จแล้ว (ยอดเงิน, เมนูลัด, สรุปการใช้จ่าย, รายการล่าสุด) แต่ดึงข้อมูลจาก `MockBankData` แบบ static |
| แท็บบัตร / จ่ายเงิน / บัญชี | ยังเป็น placeholder (`ScreenShell` + `FeatureRow`) |
| สถาปัตยกรรม | README บอกว่าใช้ MVVM แต่ยังไม่มี ViewModel เพราะ View อ่าน mock data ตรง ๆ |
| ข้อความ | ภาษาไทย hard-code ใน View และยังไม่มี localization |
| ธีม | ออกแบบมาสำหรับธีมมืด แต่ใน Light mode พื้นหลังกลายเป็นสีขาว และหัวข้อ Dashboard ที่ใช้ `.primary` กลายเป็นตัวดำ (ดูได้จาก `assets/Sample_UI.png`) |
| ข้อมูลที่ hard-code ใน View | "เงินคืนเดือนนี้ ฿12,400", "+12.8%", ชื่อผู้ใช้ "คุณนกน้อย", คำทักทาย "สวัสดีตอนเย็น" |
| ปุ่มต่าง ๆ | เมนูลัด / "ดูทั้งหมด" / "ปรับแต่ง" ยังกดไม่ได้ |
| Test | ยังไม่มี test target |
| Platform | iOS 17.0+, Swift 5, ไม่มี dependency ภายนอก |

---

## 2. ผู้ใช้เป้าหมาย

| Persona | ลักษณะ | สิ่งที่ต้องการ |
|---|---|---|
| ลูกค้าพรีเมียม | มีเงินฝากสูง ใช้บัตรเครดิตระดับ Titanium/Gold เดินทางบ่อย | ดูภาพรวมการเงินได้เร็ว โอนเงินได้ปลอดภัย และควบคุมบัตรได้เอง |
| ผู้ใช้ทั่วไปที่ใช้ภาษาอังกฤษ | ชาวต่างชาติที่อาศัยในไทย | ใช้งานแอปเป็นภาษาอังกฤษได้ครบทุกหน้า |

---

## 3. ขอบเขต

### 3.1 In scope
- iOS App: Onboarding/Login, PIN, Face ID, Dashboard, โอนเงิน, จ่ายบิล, จัดการบัตร, ประวัติรายการ, โปรไฟล์/ตั้งค่า
- Backend API: Auth, Accounts, Transactions, Transfers, Bills, Cards, Profile, Notifications
- รองรับภาษาไทยและอังกฤษ
- ใช้ธีมสว่างอย่างเดียว (บังคับ Light ทั้งแอป) ตาม design system "Porcelain Titanium"

### 3.2 Out of scope (เวอร์ชันนี้)
- เปิดบัญชีใหม่ผ่านแอป (e-KYC / NDID)
- การลงทุน (ปุ่ม "ลงทุน" จะแสดงหน้า "เร็ว ๆ นี้")
- กระเป๋าเงินต่างประเทศและการแลกเปลี่ยนเงินตรา
- iPad, Android และ Web
- Dark theme

---

## 4. Functional Requirements

ระดับความสำคัญ: **P0** = ต้องมีก่อน release, **P1** = ควรมี, **P2** = มีก็ดี

### 4.1 Authentication & Security (AUTH)

| ID | Requirement | Priority |
|---|---|---|
| AUTH-01 | ผู้ใช้ลงทะเบียนอุปกรณ์ครั้งแรกด้วย **เลขบัตรประชาชน 13 หลัก** (ตรวจ checksum) + รหัสผ่าน แล้วยืนยันด้วย OTP ทาง SMS ที่ส่งไปยังเบอร์ที่ผูกกับบัญชี | P0 |
| AUTH-02 | หลังลงทะเบียนสำเร็จ ผู้ใช้ต้องตั้ง PIN 6 หลัก โดยห้ามเป็นเลขเรียง (123456) หรือเลขซ้ำทั้งหมด (111111) | P0 |
| AUTH-03 | ผู้ใช้เลือกเปิด Face ID / Touch ID ได้ เพื่อใช้แทน PIN ตอนเปิดแอป | P0 |
| AUTH-04 | ทุกครั้งที่เปิดแอปหรือกลับมาจาก background นานเกิน 5 นาที ต้องปลดล็อกด้วย PIN หรือ Biometrics | P0 |
| AUTH-05 | ใส่ PIN ผิด 5 ครั้งติดกันจะล็อก และต้องยืนยันตัวตนใหม่ด้วย OTP | P0 |
| AUTH-06 | ถ้าไม่มีการใช้งานนาน 5 นาทีขณะเปิดแอปอยู่ ให้ล็อกหน้าจอ (session timeout) | P0 |
| AUTH-07 | ใช้ access token อายุสั้น (15 นาที) + refresh token เก็บใน Keychain | P0 |
| AUTH-08 | รองรับ "ลืม PIN" โดยยืนยันตัวตนใหม่ด้วยรหัสผ่าน + OTP | P1 |
| AUTH-09 | ผูกบัญชีได้ครั้งละ 1 อุปกรณ์ ถ้าลงทะเบียนเครื่องใหม่ เครื่องเดิมต้องถูกยกเลิกพร้อมแจ้งเตือน | P1 |
| AUTH-10 | ซ่อนเนื้อหาในแอปตอนอยู่ใน App Switcher (privacy overlay) | P0 |
| AUTH-11 | ตรวจจับอุปกรณ์ที่ jailbreak แล้ว และแสดงคำเตือนหรือจำกัดการทำธุรกรรม | P1 |

### 4.2 Dashboard (DASH)

| ID | Requirement | Priority |
|---|---|---|
| DASH-01 | แสดงบัญชีหลัก ได้แก่ ชื่อบัญชี, เลขบัญชีแบบปิดบัง (•••• 4289) และยอดคงเหลือจาก API | P0 |
| DASH-02 | แตะไอคอนตาเพื่อซ่อนหรือแสดงยอดเงิน และจำค่าที่เลือกไว้ | P1 |
| DASH-03 | ถ้ามีหลายบัญชี ให้ปัดดูบัญชีอื่นบนการ์ดยอดเงินได้ | P1 |
| DASH-04 | เมนูลัด (โอนเงิน, เติมเงิน, จ่ายบิล, ลงทุน) ต้องพาไปยัง flow ที่ถูกต้อง | P0 |
| DASH-05 | "ปรับแต่ง" ให้ผู้ใช้เลือกและเรียงเมนูลัดได้สูงสุด 4 รายการ | P2 |
| DASH-06 | สรุปการใช้จ่ายรายเดือนตามหมวดและงบประมาณ ซึ่งคำนวณจาก backend | P1 |
| DASH-07 | แสดงรายการล่าสุด 5 รายการ และกด "ดูทั้งหมด" เพื่อไปหน้าประวัติรายการ | P0 |
| DASH-08 | คำทักทายเปลี่ยนตามช่วงเวลา (เช้า/บ่าย/เย็น) และใช้ชื่อผู้ใช้จริง | P1 |
| DASH-09 | ดึงลงเพื่อรีเฟรช (pull-to-refresh) | P0 |
| DASH-10 | ตัวเลข "เงินคืนเดือนนี้" และ "ผลตอบแทนการลงทุน" ต้องมาจาก API ไม่ hard-code | P1 |

### 4.3 โอนเงิน (TRF)

| ID | Requirement | Priority |
|---|---|---|
| TRF-01 | โอนระหว่างบัญชีของตัวเอง | P0 |
| TRF-02 | โอนไปบัญชี LuxeBank ของผู้อื่น | P0 |
| TRF-03 | โอนต่างธนาคาร โดยเลือกธนาคารแล้วกรอกเลขบัญชี | P0 |
| TRF-04 | โอนผ่านพร้อมเพย์ด้วยเบอร์โทรหรือเลขบัตรประชาชน | P0 |
| TRF-05 | ก่อนยืนยัน ต้องตรวจสอบและแสดงชื่อผู้รับ (name inquiry) | P0 |
| TRF-06 | หน้ายืนยันต้องแสดงผู้รับ, ธนาคาร, จำนวนเงิน, ค่าธรรมเนียม และบันทึกช่วยจำ | P0 |
| TRF-07 | ยืนยันการโอนด้วย PIN หรือ Biometrics | P0 |
| TRF-08 | ตรวจวงเงิน: จำนวนเงินต้องมากกว่า 0, ไม่เกินยอดคงเหลือ และไม่เกินวงเงินต่อวัน (ค่าเริ่มต้น ฿200,000/วัน) | P0 |
| TRF-09 | ถ้าโอนตั้งแต่ ฿50,000 ขึ้นไปต่อครั้ง ต้องยืนยันด้วย Face ID เพิ่ม (step-up auth ตามแนวทาง ธปท.) | P0 |
| TRF-10 | แสดงสลิปพร้อม QR สำหรับตรวจสอบ บันทึกลง Photos หรือแชร์ได้ | P0 |
| TRF-11 | บันทึกผู้รับเป็น "รายการโปรด" และเลือกจากรายการล่าสุดได้ | P1 |
| TRF-12 | สแกน QR พร้อมเพย์ / Thai QR เพื่อจ่ายเงิน | P1 |
| TRF-13 | ตั้งโอนล่วงหน้าหรือโอนประจำ | P2 |
| TRF-14 | ใส่ idempotency key ทุกคำขอโอน เพื่อป้องกันการโอนซ้ำเมื่อเน็ตหลุดแล้วกดซ้ำ | P0 |

### 4.4 จ่ายบิล / เติมเงิน (BILL)

| ID | Requirement | Priority |
|---|---|---|
| BILL-01 | เลือกผู้ให้บริการตามหมวด (ไฟฟ้า, น้ำ, โทรศัพท์, บัตรเครดิต, ประกัน) | P0 |
| BILL-02 | กรอกเลขอ้างอิง (Ref1/Ref2) หรือสแกนบาร์โค้ด/QR บนใบแจ้งหนี้ | P0 |
| BILL-03 | บันทึกบิลประจำ ซึ่งตรงกับ "บิลที่ตั้งไว้ – รอชำระ N รายการ" ในหน้า placeholder เดิม | P1 |
| BILL-04 | เติมเงินมือถือหรือ e-Wallet (เมนู "เติมเงิน") | P1 |
| BILL-05 | ใช้ขั้นตอนยืนยันและสลิปเดียวกับ TRF-06, TRF-07 และ TRF-10 | P0 |

### 4.5 จัดการบัตร (CARD)

| ID | Requirement | Priority |
|---|---|---|
| CARD-01 | แสดงบัตรทั้งหมด (เดบิต/เครดิต) เป็นการ์ดเลื่อนดูได้ โดยแสดงเลขบัตร 4 หลักท้าย | P0 |
| CARD-02 | บัตรเครดิตต้องแสดงวงเงิน, ยอดใช้ไป, วงเงินคงเหลือ, ยอดชำระขั้นต่ำ และวันครบกำหนด | P0 |
| CARD-03 | ระงับบัตรชั่วคราวและเปิดกลับได้ทันที | P0 |
| CARD-04 | แจ้งบัตรหายหรือถูกขโมย เพื่อปิดถาวรและขอบัตรใหม่ (ต้องยืนยัน PIN) | P0 |
| CARD-05 | เปิด/ปิดการใช้งานแต่ละช่องทาง ได้แก่ ออนไลน์, ต่างประเทศ, Contactless และ ATM | P1 |
| CARD-06 | ตั้งวงเงินใช้จ่ายต่อวัน (ไม่เกินวงเงินที่ธนาคารอนุมัติ) | P1 |
| CARD-07 | ดูเลขบัตรเต็มและ CVV ได้หลังยืนยันด้วย Biometrics และแสดงอยู่ 30 วินาทีแล้วซ่อน | P1 |
| CARD-08 | ดูคะแนนสะสมและสิทธิประโยชน์ (เช่น คุ้มครองการเดินทาง) | P1 |
| CARD-09 | ดูรายการใช้จ่ายของบัตรแต่ละใบ | P0 |

### 4.6 ประวัติรายการ (TXN)

| ID | Requirement | Priority |
|---|---|---|
| TXN-01 | แสดงรายการทั้งหมดเรียงจากใหม่ไปเก่า โดยแบ่งกลุ่มตามวัน และโหลดเพิ่มทีละหน้า (cursor pagination) | P0 |
| TXN-02 | ค้นหาจากชื่อร้านค้าหรือบันทึกช่วยจำ | P0 |
| TXN-03 | กรองตามบัญชี/บัตร, ช่วงวันที่, หมวด และประเภท (เข้า/ออก) | P0 |
| TXN-04 | หน้ารายละเอียดรายการแสดงเลขอ้างอิง, วันเวลา, ช่องทาง, หมวด และสลิป (ถ้ามี) | P0 |
| TXN-05 | ผู้ใช้เปลี่ยนหมวดรายการเองได้ และนำไปใช้ในสรุปการใช้จ่าย | P2 |
| TXN-06 | ขอ statement ย้อนหลังเป็น PDF ได้สูงสุด 12 เดือน | P2 |

### 4.7 โปรไฟล์และการตั้งค่า (PROF)

| ID | Requirement | Priority |
|---|---|---|
| PROF-01 | แสดงชื่อ, ระดับลูกค้า (Gold ฯลฯ), ผู้ดูแลบัญชี (Relationship Manager) และช่องทางติดต่อ | P0 |
| PROF-02 | เปลี่ยน PIN | P0 |
| PROF-03 | เปิด/ปิด Face ID | P0 |
| PROF-04 | เปลี่ยนภาษา ไทย/อังกฤษ ภายในแอป (ไม่ต้องเปลี่ยนภาษาเครื่อง) | P0 |
| PROF-05 | ตั้งค่าการแจ้งเตือน ได้แก่ ธุรกรรม, ความปลอดภัย และโปรโมชัน | P1 |
| PROF-06 | ดูอุปกรณ์ที่ลงทะเบียนอยู่ | P1 |
| PROF-07 | ติดต่อ RM ด้วยการโทรหรือแชท | P2 |
| PROF-08 | ออกจากระบบและยกเลิกการผูกอุปกรณ์ | P0 |
| PROF-09 | ดูนโยบายความเป็นส่วนตัว (PDPA) และข้อกำหนดการใช้งาน | P0 |

### 4.8 การแจ้งเตือน (NOTI)

| ID | Requirement | Priority |
|---|---|---|
| NOTI-01 | ส่ง Push notification ทุกครั้งที่มีเงินเข้า/ออก | P0 |
| NOTI-02 | ส่ง Push แจ้งเหตุการณ์ด้านความปลอดภัย เช่น login จากเครื่องใหม่ เปลี่ยน PIN หรือระงับบัตร | P0 |
| NOTI-03 | มีกล่องข้อความแจ้งเตือนภายในแอป | P2 |

---

## 5. Non-Functional Requirements

| ID | หมวด | Requirement |
|---|---|---|
| NFR-01 | Performance | Cold start จนเห็นหน้า PIN ภายใน 2 วินาที (iPhone 12 ขึ้นไป) และ Dashboard แสดงข้อมูลภายใน 1.5 วินาทีหลังปลดล็อก |
| NFR-02 | Performance | API p95 latency ไม่เกิน 500 ms สำหรับคำขออ่านข้อมูล และไม่เกิน 2 วินาทีสำหรับการโอน |
| NFR-03 | Availability | Backend uptime 99.9% |
| NFR-04 | Security | ใช้ TLS 1.2+ พร้อม certificate pinning และห้ามเก็บข้อมูลสำคัญใน `UserDefaults` (token เก็บใน Keychain ด้วย `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) |
| NFR-05 | Security | ห้ามบันทึกเลขบัญชีเต็ม เลขบัตร หรือ token ลง log และปิดการ screenshot บนหน้าที่แสดงเลขบัตรเต็ม |
| NFR-06 | Compliance | ทำตาม PDPA, แนวทาง Mobile Banking Security ของ ธปท., PCI DSS และมาตรฐาน OWASP ตามหัวข้อ [13](#13-มาตรฐานความปลอดภัยและเกณฑ์การพัฒนา) |
| NFR-07 | Reliability | ทุกธุรกรรมการเงินต้องเป็น ACID และ idempotent โดยเก็บแบบบัญชีคู่ (double-entry ledger) |
| NFR-08 | Offline | ถ้าไม่มีเน็ต ให้แสดงข้อมูลล่าสุดที่ cache ไว้พร้อมป้าย "ออฟไลน์" และปิดปุ่มทำธุรกรรม |
| NFR-09 | Accessibility | รองรับ Dynamic Type และ VoiceOver และสีต้องผ่าน contrast WCAG AA |
| NFR-10 | Localization | ไม่มีข้อความ hard-code ใน View ทุกข้อความต้องอยู่ใน String Catalog (`Localizable.xcstrings`) และจัดรูปแบบเงิน/วันที่ตาม locale (ปฏิทินพุทธศักราชเมื่อใช้ภาษาไทย) |
| NFR-11 | Theme | บังคับใช้ธีมสว่างด้วย `.preferredColorScheme(.light)` และใช้สีจาก `BankTheme` (Porcelain Titanium) เท่านั้น ห้ามใช้สีระบบที่เปลี่ยนตามธีม |
| NFR-12 | Quality | Unit test ครอบคลุม ViewModel/Domain อย่างน้อย 70% และมี UI test สำหรับ flow login และโอนเงิน |
| NFR-13 | Observability | มี crash reporting และ structured log ฝั่ง backend พร้อม trace ID ที่ส่งต่อจาก client |

---

## 6. สถาปัตยกรรม iOS App

### 6.1 Tech stack
- Swift 5.10+ / SwiftUI และ iOS 17.0+ (ใช้ Observation `@Observable`)
- Swift Concurrency (`async/await`) สำหรับงาน network
- MVVM + Repository pattern
- `URLSession` (ไม่ใช้ dependency ภายนอก ตามแนวทางเดิมของโปรเจกต์)
- `LocalAuthentication` สำหรับ Face ID และ `Security` สำหรับ Keychain
- `AVFoundation` / `VisionKit` สำหรับสแกน QR และบาร์โค้ด
- Swift Testing / XCTest สำหรับ unit test และ UI test

### 6.2 Layers

```
┌────────────────────────────────────────────┐
│ Presentation  (SwiftUI Views + ViewModels) │  @Observable, @MainActor
├────────────────────────────────────────────┤
│ Domain        (Models, Use cases)          │  pure Swift, testable
├────────────────────────────────────────────┤
│ Data          (Repositories)               │  protocol + Remote/Mock impl
├────────────────────────────────────────────┤
│ Infrastructure (APIClient, Keychain,       │
│   BiometricAuth, SessionManager, Cache)    │
└────────────────────────────────────────────┘
```

- Repository ทุกตัวต้องเป็น `protocol` และมี 2 implementation คือ `Remote…Repository` (เรียก API) และ `Mock…Repository` (ต่อยอดจาก `MockBankData` เดิม) ใช้ mock สำหรับ SwiftUI Preview, test และการพัฒนาตอนที่ backend ยังไม่พร้อม
- สลับ implementation ผ่าน `AppEnvironment` (dependency container) ตาม build configuration: `Debug-Mock`, `Debug`, `Release`

### 6.3 โครงสร้างโฟลเดอร์ที่เสนอ

```
LuxeBank/
├── App/                 LuxeBankApp, AppEnvironment, RootView (auth gate)
├── DesignSystem/        BankTheme, PremiumPanel, LuxeTabBar, components
├── Core/
│   ├── Networking/      APIClient, Endpoint, APIError, TokenRefresher
│   ├── Security/        KeychainStore, BiometricAuthenticator, PinValidator
│   └── Session/         SessionManager, InactivityMonitor
├── Domain/Models/       Account, Transaction, Card, Transfer, Bill, UserProfile
├── Data/
│   ├── Repositories/    AuthRepository, AccountRepository, ...
│   └── Mock/            MockBankData, Mock…Repository
├── Features/
│   ├── Auth/            Login, OTP, PinSetup, PinEntry
│   ├── Dashboard/
│   ├── Transfer/        Recipient, Amount, Confirm, Slip
│   ├── Bills/
│   ├── Cards/
│   ├── Transactions/
│   └── Profile/
└── Resources/           Localizable.xcstrings, Assets.xcassets
LuxeBankTests/
LuxeBankUITests/
```

### 6.4 Navigation
- `RootView` ตัดสินใจจากสถานะ session: `.unregistered` → Onboarding/Login, `.locked` → PinEntry, `.unlocked` → `ContentView` (แท็บ)
- แต่ละแท็บใช้ `NavigationStack` แยกกัน และ flow โอนเงิน/จ่ายบิลเปิดเป็น `fullScreenCover`
- `LuxeTabBar` แบบ custom ยังใช้ต่อ แต่ต้องซ่อนเมื่อ push เข้าหน้าย่อย

### 6.5 การจัดการเงิน
- เปลี่ยนชนิดของ `balance` และ `amount` จาก `Double` เป็น `Decimal` ฝั่งแอป และฝั่ง API ใช้ **string** หรือ **integer หน่วยสตางค์** เพื่อป้องกันความคลาดเคลื่อนของทศนิยม
- `BankFormatter.currency` ต้องรับ `Decimal` และใช้ locale ตามภาษาที่เลือก

---

## 7. สถาปัตยกรรม Backend

| ส่วน | ที่ตกลง |
|---|---|
| Language / Framework | **Kotlin 2.x + Spring Boot 4.x** (Spring Framework 7, Jackson 3) (JDK 21) |
| Build | **Gradle (Kotlin DSL)** |
| Web / Validation | Spring Web MVC + Jakarta Validation |
| Security | Spring Security + OAuth2 Resource Server (JWT RS256) |
| Database | PostgreSQL 16 + Spring Data JPA, migration ด้วย **Flyway** |
| Cache / Rate limit / OTP | Redis (Spring Data Redis + Bucket4j) |
| Async / Push | Spring `@Async` + outbox table สำหรับงานส่ง APNs |
| API spec | springdoc-openapi (OpenAPI 3.1) |
| Testing | JUnit 5, MockK, Testcontainers (PostgreSQL/Redis), Spring REST Docs หรือ contract test |
| Observability | Spring Boot Actuator + Micrometer + structured JSON logging |
| Local / Deploy | **Docker Compose** (app + postgres + redis) ส่วน cloud ยังไม่ได้เลือก ทำ image ให้ย้ายไป cloud ไหนก็ได้ |

### 7.0 External integrations (Adapter pattern)

เป้าหมายคือ **ใช้งาน production จริง** แต่ยังไม่มีใบอนุญาตหรือสัญญากับผู้ให้บริการ จึงแยกระบบภายนอกทุกตัวเป็น port (interface) แล้วเขียน adapter 2 แบบ

| Port | Stub adapter (dev/test) | Production adapter (ภายหลัง) |
|---|---|---|
| `OtpSender` | log OTP ลง console, OTP คงที่ `000000` ใน profile `local` | SMS gateway |
| `InterbankTransferGateway` | ตอบสำเร็จหรือล้มเหลวตามเลขบัญชีทดสอบที่กำหนด | ITMX / ธนาคารพันธมิตร |
| `PromptPayDirectory` | ใช้ตารางผู้รับจำลอง | PromptPay lookup |
| `BillPaymentGateway` | ใช้รายชื่อ biller และยอดค้างชำระจำลอง | Bill payment aggregator |
| `CardProcessor` | เก็บบัตรจำลองใน DB และสร้าง PAN ทดสอบ | Card processor (เก็บข้อมูลบัตรนอก LuxeBank) |
| `PushNotifier` | log | APNs |
| `IdentityVerifier` | ตรวจเฉพาะ checksum ของเลขบัตรประชาชน | ระบบ KYC ของธนาคาร |

- เลือก adapter ผ่าน Spring profile (`local`, `staging`, `prod`)
- **profile `prod` ต้องไม่ start ถ้ายังใช้ stub adapter** (fail fast ตอน boot) เพื่อป้องกันการปล่อยระบบที่ยังจำลองเงินขึ้น production
- ก่อนเปิดใช้งานจริงต้องทำ security audit, pen test และขออนุญาตจากหน่วยงานกำกับให้เรียบร้อย (ดู M6)

### 7.1 Modules
`auth`, `users`, `devices`, `accounts`, `ledger`, `transfers`, `bills`, `cards`, `transactions`, `insights`, `notifications`, `audit`

### 7.2 Ledger
- ทุกการเคลื่อนไหวของเงินบันทึกเป็น `journal_entry` ที่มี `posting` อย่างน้อย 2 รายการ และผลรวมต้องเป็น 0
- ยอดคงเหลือคำนวณจาก posting และทำ snapshot เพื่อให้อ่านได้เร็ว
- การโอนใช้ `SELECT … FOR UPDATE` บนบัญชีต้นทางภายใน transaction เดียว
- `audit_log` ต้องเป็นแบบ append-only และบันทึก actor, action, IP, device และ trace ID

### 7.3 โครงสร้าง Monorepo

```
LukeBankApp/
├── ios/                      ย้าย LuxeBank/ + LuxeBank.xcodeproj มาไว้ที่นี่
├── backend/
│   ├── build.gradle.kts
│   ├── src/main/kotlin/com/luxebank/
│   │   ├── auth/  users/  devices/  accounts/  ledger/
│   │   ├── transfers/  bills/  cards/  transactions/
│   │   ├── insights/  notifications/  audit/
│   │   ├── integration/      ports + stub/ + (prod/ ภายหลัง)
│   │   └── common/           error handling, idempotency, tracing
│   ├── src/main/resources/db/migration/   Flyway scripts
│   └── src/test/kotlin/
├── api/openapi.yaml          contract กลางระหว่าง iOS และ backend
├── docker-compose.yml
└── docs/SPEC.md
```

---

## 8. Data Model (หลัก)

```
User(id, citizen_id_hash, email, phone, full_name_th, full_name_en,
     tier[Silver|Gold|Platinum], rm_id, preferred_language, created_at)

Device(id, user_id, device_name, public_key, push_token,
       biometric_enabled, registered_at, revoked_at)

Account(id, user_id, type[savings|current], name, account_number,
        currency='THB', status, daily_transfer_limit)

JournalEntry(id, type[transfer|bill|card|fee|interest], reference_no,
             idempotency_key UNIQUE, status[pending|posted|failed|reversed],
             created_at)
Posting(id, journal_entry_id, account_id, amount_satang BIGINT)   -- มีเครื่องหมาย: + เข้าบัญชี, − ออกจากบัญชี (D16)

Transaction(id, account_id | card_id, journal_entry_id, merchant, monogram,
            category, amount_satang (มีเครื่องหมาย), memo,
            channel, occurred_at)            -- read model

SavingsGoal(id, user_id, account_id, name, target_satang)   -- ยอดออม = ยอดคงเหลือของ account_id

Transfer(id, journal_entry_id, from_account_id, to_type[own|internal|other_bank|promptpay],
         to_bank_code, to_account_or_proxy, to_name, amount_satang,
         fee_satang, memo, slip_qr_payload, created_at)

Payee(id, user_id, nickname, type, bank_code, account_or_proxy, name, is_favorite)

Biller(id, code, name_th, name_en, category, ref1_label, ref2_label)
SavedBill(id, user_id, biller_id, ref1, ref2, nickname)

Card(id, user_id, account_id?, type[debit|credit], product_name,
     last4, token_ref, status[active|frozen|lost|closed],
     credit_limit_satang, daily_limit_satang,
     online_enabled, overseas_enabled, contactless_enabled, atm_enabled,
     reward_points)

SpendingBudget(id, user_id, kind[lifestyle|travel], month, limit_satang)   -- ใช้งบเดือนล่าสุดที่ ≤ เดือนที่ถาม
NotificationPref(user_id, transactions, security, marketing)
AuditLog(id, user_id, action, metadata JSONB, ip, device_id, trace_id, created_at)
```

> ไม่เก็บเลขบัตรเต็มหรือ CVV ใน DB ของ LuxeBank แต่เก็บ `token_ref` ที่ได้จาก card processor (PCI scope reduction)

---

## 9. API (v1)

Base URL `/api/v1` · JSON · Header ที่ต้องส่ง: `Authorization: Bearer`, `Accept-Language: th|en`, `X-Device-Id`, `X-Trace-Id` · คำขอที่เปลี่ยนเงินต้องมี `Idempotency-Key`

### Auth
| Method | Path | คำอธิบาย |
|---|---|---|
| POST | `/auth/register` | ตรวจเลขบัตรประชาชน + รหัสผ่าน แล้วส่ง OTP ได้ `otpRef`, `maskedPhone` |
| POST | `/auth/otp/verify` | ยืนยัน OTP ได้ `registrationToken` (ใช้ได้ครั้งเดียว อายุ 10 นาที) |
| POST | `/auth/devices` | ตั้ง PIN + ผูกเครื่องด้วย public key ของ Secure Enclave (เครื่องเดิมถูกยกเลิก) ได้ session |
| POST | `/auth/challenge` | ขอ challenge ใช้ครั้งเดียว อายุ 2 นาที |
| POST | `/auth/login` | ส่งลายเซ็น challenge + PIN (`method: PIN`) หรือลายเซ็นจาก key ที่ล็อกด้วย Face ID (`method: BIOMETRIC`) ได้ session |
| POST | `/auth/refresh` | หมุน refresh token; ถ้าใช้ซ้ำจะยกเลิกทั้ง family |
| POST | `/auth/logout` | ยกเลิกเครื่องและ token ทั้งหมด |
| PUT / DELETE | `/auth/biometric` | ลงทะเบียน / ลบ public key สำหรับ Face ID |
| PUT | `/auth/pin` | เปลี่ยน PIN (ต้องใส่ PIN เดิม) |

### Accounts & Transactions
| Method | Path | คำอธิบาย |
|---|---|---|
| GET | `/me` | ชื่อตามภาษา (`Accept-Language`), ระดับลูกค้า, เบอร์แบบ mask |
| GET | `/accounts` | รายการบัญชีพร้อมยอดคงเหลือ |
| GET | `/accounts/{id}/transactions?cursor&limit&from&to&category&direction&q` | ประวัติรายการ |
| GET | `/transactions/{id}` | รายละเอียดรายการ |
| PATCH | `/transactions/{id}` | แก้หมวด หรือ memo (`clearMemo: true` เพื่อลบบันทึก) |
| GET | `/insights/spending?month=2026-10` | สรุปตามหมวดเทียบกับงบ |
| GET | `/dashboard` | ข้อมูลรวมสำหรับหน้าแรก (บัญชีหลัก, cashback, ผลตอบแทน, รายการล่าสุด 5 รายการ, insights) |

### Transfers & Bills
| Method | Path | คำอธิบาย |
|---|---|---|
| GET | `/banks` | รายชื่อธนาคาร |
| POST | `/transfers/inquiry` | ตรวจชื่อผู้รับและค่าธรรมเนียม แล้วรับ `inquiry_id` (อายุ 5 นาที) |
| POST | `/transfers` | ยืนยันการโอนด้วย `inquiry_id` และ auth proof แล้วรับผลพร้อมสลิป |
| GET | `/payees` · POST · DELETE `/payees/{id}` | จัดการรายการโปรด |
| GET | `/billers?category` | รายชื่อผู้ให้บริการ |
| POST | `/bills/inquiry` | ตรวจ Ref และยอดค้างชำระ |
| POST | `/bills/payments` | ชำระบิล |
| GET/POST/DELETE | `/bills/saved` | บิลที่บันทึกไว้ |
| POST | `/qr/parse` | แปลง Thai QR payload เป็นข้อมูลผู้รับ |

### Cards
| Method | Path | คำอธิบาย |
|---|---|---|
| GET | `/cards` | รายการบัตร |
| GET | `/cards/{id}` | รายละเอียด วงเงิน และคะแนน |
| GET | `/cards/{id}/transactions` | รายการของบัตร |
| POST | `/cards/{id}/freeze` · `/unfreeze` | ระงับหรือเปิดบัตร |
| POST | `/cards/{id}/report-lost` | แจ้งหายและออกบัตรใหม่ |
| PATCH | `/cards/{id}/controls` | ตั้งค่าช่องทางการใช้งานและวงเงินต่อวัน |
| POST | `/cards/{id}/sensitive` | ขอเลขบัตรเต็มและ CVV (ต้องมี step-up proof, ข้อมูลเข้ารหัสด้วย device key) |

### Profile & Notifications
| Method | Path | คำอธิบาย |
|---|---|---|
| PATCH | `/me/preferences` | ภาษา และการตั้งค่าการแจ้งเตือน |
| GET | `/me/devices` | อุปกรณ์ที่ลงทะเบียน |
| PUT | `/me/devices/current/push-token` | อัปเดต APNs token |

### รูปแบบ Error
```json
{
  "error": {
    "code": "INSUFFICIENT_FUNDS",
    "message": "ยอดเงินในบัญชีไม่เพียงพอ",
    "trace_id": "8f2c…"
  }
}
```
Error code หลัก: `INVALID_CREDENTIALS`, `ACCOUNT_LOCKED`, `OTP_INVALID`, `OTP_EXPIRED`, `OTP_LOCKED`, `PIN_INVALID` (มี `remainingAttempts`), `PIN_LOCKED`, `PIN_POLICY_VIOLATION`, `CHALLENGE_INVALID`, `SIGNATURE_INVALID`, `TOKEN_INVALID`, `RATE_LIMITED`, `STEP_UP_REQUIRED`, `INSUFFICIENT_FUNDS`, `DAILY_LIMIT_EXCEEDED`, `RECIPIENT_NOT_FOUND`, `INQUIRY_EXPIRED`, `DUPLICATE_REQUEST`, `CARD_FROZEN`, `SERVICE_UNAVAILABLE`

---

## 10. หน้าจอและ User Flow

### 10.1 รายการหน้าจอ
| # | หน้าจอ | Req |
|---|---|---|
| S01 | Welcome / เลือกภาษา | PROF-04 |
| S02 | Login (ข้อมูลยืนยันตัวตน + รหัสผ่าน) | AUTH-01 |
| S03 | OTP | AUTH-01, 05 |
| S04 | ตั้ง PIN / ยืนยัน PIN | AUTH-02 |
| S05 | เปิด Face ID | AUTH-03 |
| S06 | Lock screen (PIN pad + Face ID) | AUTH-04 |
| S07 | Dashboard (ปรับจากของเดิม) | DASH-* |
| S08 | โอนเงิน: เลือกผู้รับ | TRF-01–04, 11 |
| S09 | โอนเงิน: กรอกจำนวน | TRF-08 |
| S10 | โอนเงิน: ยืนยัน | TRF-05–07, 09 |
| S11 | สลิป | TRF-10 |
| S12 | สแกน QR | TRF-12, BILL-02 |
| S13 | จ่ายบิล: เลือกผู้ให้บริการ / บิลที่บันทึก | BILL-01, 03 |
| S14 | จ่ายบิล: กรอก Ref และจำนวน | BILL-02 |
| S15 | บัตร: รายการบัตร | CARD-01, 02, 08 |
| S16 | บัตร: รายละเอียดและการควบคุม | CARD-03–07, 09 |
| S17 | ประวัติรายการ (ค้นหาและกรอง) | TXN-01–03 |
| S18 | รายละเอียดรายการ | TXN-04 |
| S19 | โปรไฟล์ | PROF-01, 07 |
| S20 | ตั้งค่า (ภาษา, PIN, Face ID, แจ้งเตือน, อุปกรณ์) | PROF-02–06, 08 |
| S21 | แท็บจ่ายเงิน (ทางลัดโอน/บิล/QR/เติมเงิน, รายการโปรด, บิลที่รอชำระ) | TRF-11, BILL-03 |

UX/UI mockup ทุกหน้าจอ: https://claude.ai/artifact/CcC36hWMeQBgVPt8Cpjm14

### 10.2 Flow โอนเงิน
```
Dashboard ─▶ [โอนเงิน] ─▶ S08 เลือก/กรอกผู้รับ ─▶ S09 จำนวน + memo
   ─▶ POST /transfers/inquiry ─▶ S10 ยืนยัน (ชื่อผู้รับ, ค่าธรรมเนียม)
   ─▶ PIN/Face ID (≥ ฿50,000 บังคับ Face ID) ─▶ POST /transfers
   ─▶ สำเร็จ: S11 สลิป ─▶ [เสร็จสิ้น] กลับ Dashboard (รีเฟรชยอด)
   ─▶ ล้มเหลว: แสดง error ตาม code และให้แก้ไขหรือลองใหม่ (ใช้ idempotency key เดิม)
```

### 10.3 Flow เปิดแอป
```
Launch ─▶ มี device binding?
   ├─ ไม่มี ─▶ S01 → S02 → S03 → S04 → S05 → Dashboard
   └─ มี ──▶ S06 Lock ─▶ Face ID / PIN ─▶ POST /auth/login ─▶ Dashboard
```

### 10.4 สถานะที่ทุกหน้าต้องรองรับ
Loading (skeleton), Content, Empty, Error (มีปุ่มลองใหม่), Offline (ข้อมูลจาก cache)

---

## 11. แผนการพัฒนา (Milestones)

| Phase | งาน | ผลลัพธ์ |
|---|---|---|
| **M0 Foundation** | จัด monorepo (`ios/`, `backend/`, `api/`), ตั้งโปรเจกต์ Spring Boot + Docker Compose, แก้ธีมเป็น Dark only, ย้ายข้อความไป String Catalog (TH/EN), จัดโครงสร้างโฟลเดอร์, เพิ่ม ViewModel + Repository protocol + Mock repo, เปลี่ยนจำนวนเงินเป็น `Decimal`, เพิ่ม test targets, ตั้ง CI พร้อม security gates (SAST, SCA, gitleaks, Trivy, MobSF) และ threat model ตั้งต้น | แอปเดิมทำงานเหมือนเดิมบนสถาปัตยกรรมใหม่ |
| **M1 Auth** | หน้าจอ S01–S06, Keychain, Biometrics, SessionManager · Backend: auth, users, devices, OTP stub | เข้าสู่ระบบและล็อกแอปได้ครบ flow |
| **M2 Accounts & History** | Backend: accounts, ledger, transactions, dashboard, insights · App: ต่อ Dashboard กับ API, S17–S18 | ข้อมูลจริงบนหน้าแรกและประวัติรายการ |
| **M3 Transfer & Bills** | Backend: transfers, payees, bills, QR (sandbox) · App: S08–S14 | โอนและจ่ายบิลได้ end-to-end บน sandbox |
| **M4 Cards** | Backend: cards (stub processor) · App: S15–S16 | จัดการบัตรได้ครบ |
| **M5 Profile & Notifications** | S19–S20, APNs, การตั้งค่าการแจ้งเตือน | ฟีเจอร์ครบตาม scope |
| **M6 Hardening** | Security review, pen test, accessibility audit, performance, UAT | พร้อม release บน stub/staging |
| **M7 Go-live** | เสียบ production adapter (SMS, ITMX, bill, card), เลือก cloud, audit และขออนุญาตจากหน่วยงานกำกับ | ใช้งานจริง (ขึ้นกับสัญญาและใบอนุญาต) |

### Definition of Done (ต่อฟีเจอร์)
- ผ่าน acceptance criteria ตาม Requirement ID
- ข้อความครบทั้ง TH และ EN
- มี unit test ของ ViewModel และ use case และ backend มี integration test ของ endpoint
- มี Preview ที่ใช้ Mock repository
- รองรับสถานะ Loading/Empty/Error/Offline
- ผ่าน CI security gates (13.4.3) และ security test cases ที่เกี่ยวข้อง (13.4.4)
- ฟีเจอร์ที่แตะเงิน ข้อมูลส่วนบุคคล หรือการยืนยันตัวตน มี threat model แนบใน PR

---

## 12. Decision Log

| # | หัวข้อ | ข้อตกลง (2026-10-10) |
|---|---|---|
| D1 | Backend stack | **Spring Boot 4** (สาย 3.5 หมด OSS support แล้ว และช่องโหว่ระดับ critical แก้เฉพาะใน Framework 7) + **Kotlin** + Gradle (Kotlin DSL), PostgreSQL, Redis |
| D2 | ระบบเงิน | เป้าหมายคือ **production จริง** แต่ยังไม่มีสัญญาหรือใบอนุญาต จึงพัฒนาด้วย adapter + stub (ดู 7.0) |
| D3 | Repo | **Monorepo** แยกเป็น `ios/`, `backend/` และ `api/` |
| D4 | ยืนยันตัวตนครั้งแรก | **เลขบัตรประชาชน + รหัสผ่าน + OTP** แล้วตั้ง PIN 6 หลัก |
| D5 | Hosting | ยังไม่เลือก cloud ระหว่างนี้ใช้ **Docker Compose** |
| D6 | iOS ขั้นต่ำ | iOS 17.0 |
| D7 | วงเงิน | โอนได้ ฿200,000/วัน และต้อง step-up ด้วย Face ID ตั้งแต่ ฿50,000/ครั้ง |
| D8 | UI | Design system ใหม่ "Porcelain Titanium" (ดู canvas UX/UI) แทน BankTheme ทอง/น้ำเงินเดิม โดยไม่มีไฟล์ Figma |
| D9 | Analytics / Crash | ยังไม่ใช้ third-party SDK |
| D10 | ภาษาและธีม | ไทย + อังกฤษ, **ธีมสว่างอย่างเดียว** (เปลี่ยนจากธีมมืดเมื่อ 2026-10-10 หลังรีวิว UX/UI) |
| D11 | Identifier | iOS Bundle ID `com.luxebank.app` · Backend package `com.luxebank` |
| D12 | Git workflow | แยก branch ต่อ milestone (เช่น `m0-foundation`) แล้วเปิด PR ให้รีวิวก่อน merge เข้า `main` |
| D13 | Apple Developer | ยังไม่มี account จึงทดสอบบน Simulator · ทดสอบ Push ด้วยไฟล์ `.apns` · Development Team ยังเว้นว่าง |
| D14 | Dev toolchain | JDK 21 (Homebrew `openjdk@21`), Docker ผ่าน Colima, Gradle wrapper |
| D16 | Ledger | จำนวนเงินใน `postings` และ `transactions` เป็น **สตางค์แบบมีเครื่องหมาย** (+ เข้า, − ออก) แทนคอลัมน์ `direction` · DB บังคับเองว่าแต่ละ entry รวมได้ 0 (constraint trigger ตอน commit), posting แก้หรือลบไม่ได้, และยอดลูกค้าติดลบไม่ได้ · เงินที่เข้าหรือออกจากธนาคารผ่านบัญชีภายใน `INT-CLEARING` |
| D17 | งบประมาณ | งบรายเดือนแบ่งเป็น 2 กลุ่มตามดีไซน์หน้าแรก: **ไลฟ์สไตล์** (อาหาร, ช้อปปิ้ง, ที่พัก, บิล, อื่น ๆ) และ **ท่องเที่ยว** (เดินทาง, ท่องเที่ยว) · โอนเงิน, ลงทุน, รายรับ และเงินคืนไม่นับเป็นการใช้จ่าย |
| D15 | Typography | ใช้ฟอนต์ระบบ **Thonburi** ทั้งแอป (ไทยและอังกฤษ) ไม่ต้อง bundle ฟอนต์เพิ่ม · ฟอนต์มีแค่น้ำหนัก Light/Regular/Bold |

### คำถามที่ยังเปิด (ไม่ block การเริ่มพัฒนา)
1. ค่าธรรมเนียมโอนต่างธนาคาร (ระหว่างนี้ตั้งเป็น ฿0)
2. ผู้ให้บริการ production แต่ละราย (SMS, ITMX/ธนาคารพันธมิตร, bill aggregator, card processor)
3. Cloud provider สำหรับ staging/production

---

## 13. มาตรฐานความปลอดภัยและเกณฑ์การพัฒนา

ทุกข้อในหัวข้อนี้เป็น **เกณฑ์บังคับ** ใช้กับทุก milestone ตั้งแต่ M0 และเป็นส่วนหนึ่งของ Definition of Done

**มาตรฐานอ้างอิง**
- OWASP Top 10:2021 (เว็บและ backend)
- OWASP API Security Top 10:2023
- OWASP Mobile Top 10:2024 และ OWASP MASVS v2 ระดับ **L2 + R** (แอปการเงิน)
- OWASP ASVS 4.0 ระดับ **L2** สำหรับ backend
- พ.ร.บ. คุ้มครองข้อมูลส่วนบุคคล (PDPA), แนวทาง Mobile Banking Security และ IT Risk ของ ธปท., PCI DSS v4.0

### 13.1 OWASP Top 10

#### 13.1.1 Backend / API (OWASP Top 10:2021 + API Top 10:2023)

| ID | ความเสี่ยง | มาตรการใน LuxeBank | วิธีตรวจสอบ |
|---|---|---|---|
| A01 / API1, API5 | Broken Access Control, BOLA, BFLA | Spring Security แบบ deny-by-default · ทุก endpoint ตรวจว่าทรัพยากรเป็นของผู้ใช้ (`account.userId == principal.userId`) ในชั้น service ไม่ใช่แค่ controller · ใช้ `@PreAuthorize` กับงานที่ต้องการสิทธิ์พิเศษ · ID ภายนอกเป็น UUID ไม่ใช่เลขเรียง | test BOLA/IDOR ทุก endpoint (เข้าถึงบัญชี/บัตร/รายการของผู้อื่นต้องได้ 404) |
| A02 | Cryptographic Failures | TLS 1.2+ (แนะนำ 1.3) + HSTS · รหัสผ่านและ PIN เก็บด้วย Argon2id + pepper ใน KMS · JWT RS256 กุญแจอยู่ใน KMS และหมุนทุก 90 วัน · ข้อมูล Restricted/Confidential เข้ารหัสระดับคอลัมน์ด้วย AES-256-GCM (envelope encryption) | review การตั้งค่า TLS (SSL Labs ระดับ A) · unit test ว่าไม่มีการเก็บ plaintext |
| A03 | Injection | ใช้ JPA/parameterized query เท่านั้น ห้ามต่อ string เป็น SQL · validate input ด้วย Jakarta Validation ที่ขอบระบบทุกจุด · จำกัดรูปแบบ (เลขบัญชี, เบอร์, จำนวนเงิน) ด้วย allowlist regex | SAST + fuzz test ที่ endpoint รับ input |
| A04 | Insecure Design | ทำ threat model (STRIDE) ทุกฟีเจอร์ที่เกี่ยวกับเงินก่อนเขียนโค้ด · กำหนด abuse case เช่น replay การโอน, เปลี่ยนจำนวนเงินหลัง inquiry, ยิงซ้ำ · บังคับ idempotency key + inquiry อายุ 5 นาที + step-up ≥ ฿50,000 | เอกสาร threat model แนบใน PR ของฟีเจอร์ |
| A05 / API8 | Security Misconfiguration | ปิด Actuator ยกเว้น `health` · ไม่คืน stack trace (ใช้ error format กลางตามหัวข้อ 9) · ตั้ง security headers · container รันด้วย non-root user และ image ขั้นต่ำ · profile `prod` fail fast ถ้ายังใช้ stub adapter | review config ทุก release + Trivy |
| A06 | Vulnerable & Outdated Components | lock dependency (Gradle lockfile, Swift Package.resolved) · สร้าง SBOM (CycloneDX) ทุก build · อัปเดต dependency อย่างน้อยเดือนละครั้ง | SCA ใน CI (ดู 13.4) |
| A07 / API2 | Identification & Authentication Failures | rate limit login/OTP/PIN ด้วย Bucket4j · ล็อกหลังผิด 5 ครั้ง · refresh token rotation พร้อมตรวจจับการใช้ token ซ้ำ (reuse detection แล้ว revoke ทั้ง family) · ผูก token กับ device key · session timeout 5 นาที | test brute force, token reuse, token ของเครื่องอื่น |
| A08 | Software & Data Integrity Failures | ตรวจ checksum ของ Gradle wrapper · CI สร้าง build provenance · คำขอโอน/จ่ายบิลต้องลงลายเซ็นด้วย device private key (Secure Enclave) และ backend ตรวจสอบ | test ว่าคำขอที่ลายเซ็นไม่ถูกต้องถูกปฏิเสธ |
| A09 | Security Logging & Monitoring Failures | audit log แบบ append-only พร้อม hash chain · log เหตุการณ์ความปลอดภัย (login ล้มเหลว, เปลี่ยน PIN, ระงับบัตร, เครื่องใหม่) และตั้ง alert · ห้าม log PII/เลขบัตร/token · ทุก log มี trace ID | review log format · test ว่า log ไม่มีข้อมูลต้องห้าม |
| A10 | SSRF | backend เรียกออกไปได้เฉพาะ host ของ integration ที่อยู่ใน allowlist · ไม่มี endpoint ใดรับ URL จากผู้ใช้ | review config egress |
| API3 | Broken Object Property Level Authorization | ใช้ DTO แยกสำหรับ request/response ทุกตัว ห้าม bind entity ตรง (ป้องกัน mass assignment) · response ส่งเฉพาะ field ที่หน้าจอต้องใช้ | contract test จาก OpenAPI |
| API4 | Unrestricted Resource Consumption | pagination สูงสุด 100 รายการ/หน้า · rate limit ต่อผู้ใช้และต่อ IP · จำกัดขนาด request body · timeout ทุกการเรียกภายนอก | load test + test เกิน limit |
| API6 | Unrestricted Access to Sensitive Business Flows | จำกัดความถี่การโอน (velocity) และวงเงินต่อวัน · ตรวจรูปแบบผิดปกติ (โอนหลายครั้งติดกันไปผู้รับใหม่) แล้วบังคับ step-up | test เกินวงเงิน/ความถี่ |
| API9 | Improper Inventory Management | `api/openapi.yaml` เป็นแหล่งความจริงเดียว · ใช้ URI versioning (`/api/v1`) · ปิด endpoint เก่าตามแผน deprecate | CI ตรวจว่า endpoint จริงตรงกับ OpenAPI |

#### 13.1.2 iOS App (OWASP Mobile Top 10:2024 + MASVS)

| ID | ความเสี่ยง | มาตรการ |
|---|---|---|
| M1 | Improper Credential Usage | ไม่มี API key หรือ secret ใด ๆ ฝังในแอป · token เก็บใน Keychain เท่านั้น |
| M3 | Insecure Authentication/Authorization | PIN และ Face ID ตรวจกับ backend ผ่าน device key ใน Secure Enclave ไม่ตัดสินผลในแอปอย่างเดียว · ใช้ `LAContext` แบบ `.biometryCurrentSet` เพื่อให้ key ใช้ไม่ได้เมื่อมีการเพิ่มใบหน้าใหม่ในเครื่อง |
| M4 | Insufficient Input/Output Validation | validate รูปแบบข้อมูลก่อนส่ง · ไม่ใช้ WebView ที่เปิด JavaScript bridge |
| M5 | Insecure Communication | ATS เปิดเต็ม ห้ามมี exception · certificate pinning (public key pinning) พร้อม backup pin |
| M6 | Inadequate Privacy Controls | ขอ permission เฉพาะที่ใช้ (กล้องสำหรับสแกน QR, Face ID, Notification, Photos แบบ add-only สำหรับบันทึกสลิป) · ไม่มี analytics ของ third-party (D9) |
| M7 | Insufficient Binary Protections | ตรวจ jailbreak และ debugger (AUTH-11) · ปิด debug log ใน Release · strip symbol |
| M8 | Security Misconfiguration | ไม่มี URL scheme ที่เรียกธุรกรรมได้โดยไม่ผ่านการปลดล็อก · ปิด backup ข้อมูลสำคัญ (`isExcludedFromBackup`) |
| M9 | Insecure Data Storage | Keychain ใช้ `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` · ไฟล์ cache ใช้ `NSFileProtectionComplete` · ห้ามเก็บข้อมูลสำคัญใน `UserDefaults`, log หรือ pasteboard · ซ่อนเนื้อหาใน App Switcher (AUTH-10) · บล็อก screenshot ตอนแสดงเลขบัตรเต็ม |
| M10 | Insufficient Cryptography | ใช้ CryptoKit / Secure Enclave เท่านั้น ห้ามเขียน crypto เอง |

### 13.2 CIA Triad

| หลัก | เป้าหมาย | มาตรการหลัก |
|---|---|---|
| **Confidentiality** (การรักษาความลับ) | ข้อมูลลูกค้าเข้าถึงได้เฉพาะเจ้าของและผู้มีสิทธิ์ | จัดชั้นข้อมูล (13.3) · เข้ารหัสระหว่างส่ง (TLS + pinning) และขณะจัดเก็บ (AES-256-GCM, Keychain) · least privilege ทั้งผู้ใช้ บริการ และพนักงาน (DB แยก role อ่าน/เขียน, ไม่มีใครเข้าถึง prod DB ตรงโดยไม่ผ่าน break-glass ที่บันทึก audit) · ปิดบังข้อมูลบนหน้าจอ (เลขบัญชี/บัตร/ชื่อผู้รับ) · MFA: device binding + PIN/Face ID + step-up |
| **Integrity** (ความถูกต้องครบถ้วน) | ยอดเงินและธุรกรรมถูกต้องเสมอ แก้ไขโดยไม่ได้รับอนุญาตไม่ได้ | ledger แบบ double-entry ที่ผลรวม posting = 0 บังคับด้วย DB constraint และตรวจซ้ำด้วย job กระทบยอดรายวัน · transaction ระดับ SERIALIZABLE/`SELECT … FOR UPDATE` · idempotency key · optimistic locking (`@Version`) · คำขอเงินลงลายเซ็นด้วย device key · audit log แบบ hash chain · จำนวนเงินเป็น `Decimal`/สตางค์ (ไม่ใช้ floating point) |
| **Availability** (ความพร้อมใช้งาน) | บริการใช้ได้ต่อเนื่องและกู้คืนได้เร็ว | SLO uptime 99.9% (NFR-03) · RTO ≤ 4 ชม. / RPO ≤ 15 นาที (ข้อเสนอ รอยืนยัน) · backup แบบ point-in-time และทดสอบ restore ทุกไตรมาส · health check + auto restart · Resilience4j (circuit breaker, timeout, retry ที่ปลอดภัยต่อ idempotency) กับ adapter ภายนอก · rate limit และ WAF/DDoS protection หน้า API · แอปทำงานแบบ offline read-only ได้ (NFR-08) |

### 13.3 Data Protection

#### 13.3.1 การจัดชั้นข้อมูล

| ชั้น | ตัวอย่าง | จัดเก็บ | ส่งผ่าน | Log | แสดงผล |
|---|---|---|---|---|---|
| **Restricted** | รหัสผ่าน, PIN, OTP, CVV, เลขบัตรเต็ม, token, private key | ไม่เก็บ หรือเก็บเป็น hash (Argon2id) · เลขบัตรอยู่ที่ card processor (เก็บแค่ `token_ref`) · CVV ห้ามเก็บเด็ดขาด | TLS + pinning · เลขบัตรเต็มเข้ารหัสด้วย device public key | ห้ามเด็ดขาด | ห้าม ยกเว้นเลขบัตรเต็มหลัง Face ID และซ่อนใน 30 วินาที |
| **Confidential** | เลขบัตรประชาชน, ชื่อ-นามสกุล, เบอร์โทร, เลขบัญชี, ยอดเงิน, รายการธุรกรรม | เข้ารหัสระดับคอลัมน์ · เลขบัตรประชาชนเก็บ hash (HMAC) แยกไว้สำหรับค้นหา | TLS + pinning | เฉพาะแบบ mask เช่น `x4289` | mask ตามหน้าจอ (เช่น `•••• 4289`, `สมชาย ใจ**`) |
| **Internal** | การตั้งค่า, หมวดรายการ, device metadata | ปกติ | TLS | ได้ | ได้ |
| **Public** | รายชื่อธนาคาร, ผู้ให้บริการบิล | ปกติ | TLS | ได้ | ได้ |

#### 13.3.2 PDPA
- **ฐานทางกฎหมาย:** ข้อมูลที่ใช้ให้บริการบัญชีใช้ฐานสัญญาและหน้าที่ตามกฎหมาย ส่วนการแจ้งเตือนโปรโมชันต้องขอความยินยอมแยก และค่าเริ่มต้นเป็นปิด (PROF-05)
- **Privacy Notice:** แสดงตอนลงทะเบียนและเปิดดูได้ตลอดจากหน้าโปรไฟล์ (PROF-09)
- **สิทธิของเจ้าของข้อมูล:** รองรับคำขอเข้าถึง แก้ไข ลบ และคัดค้าน โดยตอบภายใน 30 วัน (ทำผ่านช่องทางติดต่อ RM ในเวอร์ชันนี้)
- **ระยะเวลาเก็บรักษา:** ข้อมูลธุรกรรมเก็บตามที่กฎหมายและ ธปท. กำหนด ข้อมูลอื่นลบหรือทำให้ไม่ระบุตัวตนเมื่อหมดความจำเป็น (ระยะเวลาแน่นอนรอฝ่ายกฎหมายยืนยัน)
- **การละเมิดข้อมูล:** มีแผนรับมือ และแจ้ง สคส. ภายใน 72 ชั่วโมงเมื่อพบเหตุที่มีความเสี่ยง
- **การส่งข้อมูลไปต่างประเทศ:** เลือก cloud region ในประเทศไทยเป็นหลัก ถ้าต้องใช้ region อื่นต้องผ่านการประเมินก่อน (เกี่ยวกับ D5)
- **ข้อมูลสำหรับพัฒนาและทดสอบ:** ใช้ข้อมูลสังเคราะห์เท่านั้น ห้ามคัดลอกข้อมูล production มาใช้

#### 13.3.3 PCI DSS
- ระบบ LuxeBank ไม่เก็บ PAN และ CVV (เก็บแค่ `token_ref` จาก card processor) เพื่อลดขอบเขต PCI
- การแสดงเลขบัตรเต็ม (CARD-07) ให้ processor ส่งข้อมูลที่เข้ารหัสด้วย device public key มาตรงถึงแอป backend ส่งต่อโดยถอดรหัสไม่ได้

### 13.4 Secure Coding & Testing

#### 13.4.1 Secure SDLC
1. **ออกแบบ:** ทำ threat model (STRIDE) สำหรับฟีเจอร์ใหม่ทุกตัวที่แตะเงิน ข้อมูลส่วนบุคคล หรือการยืนยันตัวตน
2. **เขียนโค้ด:** ทำตาม coding standard ด้านล่าง
3. **รีวิว:** ทุก PR ต้องผ่าน security checklist และโค้ดส่วน auth, ledger, crypto ต้องมีผู้รีวิว 2 คน
4. **ทดสอบ:** ผ่าน CI security gates (13.4.3) ทุก PR
5. **ปล่อย:** DAST บน staging และตรวจ MASVS ทุก milestone · pen test โดยบุคคลที่สามก่อน M7 Go-live
6. **ดูแลหลังปล่อย:** monitor, แก้ช่องโหว่ตาม SLA (13.4.5) และทบทวน threat model ทุกไตรมาส

#### 13.4.2 Coding standards
- **Kotlin (backend):** ktlint + detekt · ห้าม `!!` ในโค้ด production · validate input ที่ controller ด้วย Jakarta Validation · จำนวนเงินใช้ `BigDecimal`/`Long` สตางค์ · error ที่ส่งกลับใช้รูปแบบกลาง ห้ามเปิดเผยรายละเอียดภายใน
- **Swift (iOS):** SwiftLint · ห้าม force unwrap ในโค้ดที่เกี่ยวกับ auth, network และเงิน · จำนวนเงินใช้ `Decimal` · ห้าม `print` ข้อมูลใน Release (ใช้ `Logger` พร้อม privacy `.private`)
- **ทั่วไป:** ห้าม commit secret · config แยกตาม environment · ทุก dependency ใหม่ต้องระบุเหตุผลใน PR

#### 13.4.3 CI Security Gates (ทุก PR และทุก build)

| ประเภท | เครื่องมือ (ข้อเสนอ) | เกณฑ์ผ่าน |
|---|---|---|
| Unit / Integration test | JUnit 5 + MockK + Testcontainers · Swift Testing / XCTest | ผ่านทั้งหมด · coverage ≥ 70% ทั้งระบบ และ ≥ 90% ใน `ledger`, `transfers`, `auth` |
| SAST | Semgrep (Kotlin, Swift) + CodeQL (Kotlin) | ไม่มี finding ระดับ High/Critical |
| SCA | OWASP Dependency-Check หรือ Dependabot | ไม่มี CVE ระดับ High/Critical ที่ยังไม่แก้ |
| Secret scanning | gitleaks (pre-commit + CI) | 0 finding |
| Container scan | Trivy | ไม่มีช่องโหว่ระดับ Critical |
| Mobile static scan | MobSF | ไม่มี finding ระดับ High |
| API contract + authz test | สร้างจาก `api/openapi.yaml` | ทุก endpoint มี test BOLA และ test ไม่มี token |
| DAST (ต่อ release) | OWASP ZAP baseline/API scan บน staging | ไม่มี finding ระดับ High |

#### 13.4.4 Security test cases ขั้นต่ำ
- เข้าถึงบัญชี บัตร หรือรายการของผู้ใช้อื่น (IDOR/BOLA) ต้องได้ 404
- ส่งคำขอโอนซ้ำด้วย idempotency key เดิม ต้องไม่ตัดเงินซ้ำ
- ใช้ `inquiry_id` ที่หมดอายุ หรือเปลี่ยนจำนวนเงินหลัง inquiry ต้องถูกปฏิเสธ
- จำนวนเงินติดลบ เป็นศูนย์ เกินยอดคงเหลือ เกินวงเงิน หรือทศนิยมเกิน 2 ตำแหน่ง ต้องถูกปฏิเสธ
- โอนตั้งแต่ ฿50,000 โดยไม่มี step-up proof ต้องได้ `STEP_UP_REQUIRED`
- ใส่ PIN หรือ OTP ผิดเกินกำหนด ต้องถูกล็อก และ rate limit ทำงาน
- ใช้ refresh token เดิมซ้ำ ต้อง revoke token ทั้งชุด
- คำขอที่ไม่มีลายเซ็น device key หรือลายเซ็นผิด ต้องถูกปฏิเสธ
- แอปต้องปฏิเสธการเชื่อมต่อเมื่อ certificate ไม่ตรง pin
- ตรวจว่า log, crash report และ cache ไม่มีข้อมูลชั้น Restricted/Confidential

#### 13.4.5 SLA การแก้ช่องโหว่ (ข้อเสนอ)

| ระดับ | ระยะเวลาแก้ไข |
|---|---|
| Critical | 7 วัน (ระหว่างนั้นต้องมีมาตรการบรรเทาภายใน 24 ชม.) |
| High | 30 วัน |
| Medium | 90 วัน |
| Low | ตามรอบ release |
