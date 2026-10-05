<img src="assets/icon-1024.png" width="96" align="right" alt="CarSpeed icon">

# CarSpeed

Bong bóng tốc độ nổi (tốc độ hiện tại + biển giới hạn tốc độ lấy từ app dẫn đường **Vietmap Live** hoặc **GOFA**) khi app đó đang chạy nền.
Tách ra từ tính năng bong bóng tốc độ của CarDuo (SplitCarPlay), bỏ toàn bộ phần chia màn hình.

- Dopamine rootless, iOS 15.0 – 16.6.1 (build với SDK 16.5)
- Có xe CarPlay: bong bóng **chỉ** nằm trên màn xe, không hiện trên iPhone. Không có xe: nằm trên iPhone (xoay theo hướng máy).
- Tự ẩn khi app dẫn đường hiện lại (trên iPhone hoặc CarPlay), ẩn ngay khi app bị tắt, hoặc sau 5 giây không có dữ liệu.

| App | Bundle ID |
| --- | --- |
| Vietmap Live | `vn.vietmap.live` |
| GOFA | `com.lumi.GOFA` |

Thêm app khác: thêm bundle ID vào **cuối** `SPP_NAV_APPS` / `SPP_NAV_APP_NAMES` (`src/common.h`), vào `CarSpeed.plist`, thêm khoá bật/tắt trong `SPPPrefs.mm` và `carspeedprefs/SPPRootListController.m`.

## Thao tác

| Thao tác | Kết quả |
| --- | --- |
| Kéo | Di chuyển bong bóng (nhớ vị trí riêng cho iPhone / xe) |
| 2 ngón | Phóng to / thu nhỏ, lưu riêng cho iPhone / CarPlay (đồng bộ với Cài đặt) |
| Chạm | Mở lại app đang cấp tốc độ (trên xe: giao diện CarPlay của app) |
| Giữ 2 giây | Viền đỏ chạy quanh bong bóng, chạy hết vòng thì thoát hẳn app đó (thả tay sớm để huỷ) |

Cài đặt > CarSpeed (ngôn ngữ đổi ở nút 🌐 góc phải trên: Tự động / Tiếng Việt / English):

| Nhóm | Mục |
| --- | --- |
| (đầu trang) | Bật bong bóng |
| Giao diện | Kiểu hiển thị (màn chọn riêng, chọn là xem thử ngay) · Hiện icon app · Xem thử 10 giây |
| Kích thước | Trên iPhone · Trên CarPlay (60–220, 100 = mặc định) · Đặt lại vị trí & kích thước |
| Nguồn tốc độ | Vietmap Live · GOFA (kèm icon app) |
| Thao tác | Bảng nhắc các thao tác trên bong bóng |

14 kiểu, kiểu nào cũng có icon của app đang cấp tốc độ (thứ tự = giá trị `Style` = enum `SPPStyle` trong `src/SPPBubble.mm`):

| Nhóm | Kiểu |
| --- | --- |
| Thẻ & viên thuốc | Thẻ · Thẻ sáng · Kính mờ · Viên thuốc đôi · Live View · Cột dọc · Đèn LED |
| Tròn | Biển báo lớn · Đĩa màu theo tốc độ · Đồng hồ cung · Đồng hồ kim |
| HarmonyOS | Thẻ HarmonyOS · Vòng kép HarmonyOS · Bán nguyệt HarmonyOS |

Icon: `carspeedprefs/Resources/icon*.png` (Cài đặt), `CarSpeed.png` (icon gói trong Sileo/Zebra), bản gốc `assets/icon-1024.png` — vẽ lại bằng `powershell -File assets/make-icon.ps1 -Out <thư mục>` (Windows, cần font Bahnschrift).

## Phát hành

Đổi `Version` trong `control` (và `CFBundleShortVersionString` trong `carspeedprefs/Resources/Info.plist`), commit, rồi `git tag v<Version> && git push --tags`. CI build bản release (`FINALPACKAGE=1`) và đính `CarSpeed_<Version>_rootless.deb` vào GitHub Release. Gói mới tự gỡ bản cũ `com.anlai97.speedpop` khi cài (Conflicts/Replaces); cài đặt cũ không được chuyển sang.

## Cách hoạt động

| Process | File | Việc |
| --- | --- | --- |
| Vietmap Live / GOFA | `src/hooks/NavApp.xm` | GPS riêng (khi app bật GPS) + quét màn hình lấy giới hạn → Darwin notify `carspeed.speed` (kèm chỉ số app) |
| SpringBoard | `src/hooks/SpringBoard.xm`, `src/SPPBubble.mm` | Nhận tốc độ, vẽ bong bóng trên cửa sổ riêng (màn xe nếu có CarPlay, ngược lại iPhone) |
| CarPlay (`com.apple.CarPlayApp`) | `src/hooks/CarPlay.xm` | Chạm bong bóng trên xe → mở đúng app qua `DBDashboard handleEvent:` |

Log: `/var/mobile/Documents/CarSpeed.log` (xem bằng Filza).

## Build

Không cần Theos trên máy: push lên GitHub, workflow `.github/workflows/build.yml` build trên macOS và đưa file `.deb` vào mục Artifacts của lần chạy.

Nếu đang cài CarDuo thì tắt bong bóng tốc độ trong Cài đặt CarDuo để không bị 2 bong bóng.
