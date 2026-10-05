<img src="assets/icon-1024.png" width="96" align="right" alt="SpeedPop icon">

# SpeedPop

Bong bóng tốc độ nổi (tốc độ hiện tại + biển giới hạn tốc độ lấy từ app dẫn đường **Vietmap Live** hoặc **GOFA**) khi app đó đang chạy nền.
Tách ra từ tính năng bong bóng tốc độ của CarDuo (SplitCarPlay), bỏ toàn bộ phần chia màn hình.

- Dopamine rootless, iOS 15.0 – 16.6.1 (build với SDK 16.5)
- Có xe CarPlay: bong bóng **chỉ** nằm trên màn xe, không hiện trên iPhone. Không có xe: nằm trên iPhone (xoay theo hướng máy).
- Tự ẩn khi app dẫn đường hiện lại (trên iPhone hoặc CarPlay) hoặc 5 giây không có dữ liệu.

| App | Bundle ID |
| --- | --- |
| Vietmap Live | `vn.vietmap.live` |
| GOFA | `com.lumi.GOFA` |

Thêm app khác: thêm bundle ID vào **cuối** `SPP_NAV_APPS` / `SPP_NAV_APP_NAMES` (`src/common.h`), vào `SpeedPop.plist`, thêm khoá bật/tắt trong `SPPPrefs.mm` và `Root.plist`.

## Thao tác

| Thao tác | Kết quả |
| --- | --- |
| Kéo | Di chuyển bong bóng (nhớ vị trí riêng cho iPhone / xe) |
| 2 ngón | Phóng to / thu nhỏ (nhớ lại) |
| Chạm | Mở lại app đang cấp tốc độ (trên xe: giao diện CarPlay của app) |
| Giữ 0.5s | Hiện nút X đỏ: bấm để tắt hẳn app đó |

Cài đặt > SpeedPop: bật/tắt, 6 kiểu hiển thị (Vietmap, Tối giản, Biển báo, Đồng hồ, Thanh HUD, Màu tốc độ), xem thử 10 giây, bật/tắt riêng từng app (Vietmap Live / GOFA).

Icon: `speedpopprefs/Resources/icon*.png` (Cài đặt), `SpeedPop.png` (icon gói trong Sileo/Zebra), bản gốc `assets/icon-1024.png`.

## Cách hoạt động

| Process | File | Việc |
| --- | --- | --- |
| Vietmap Live / GOFA | `src/hooks/NavApp.xm` | GPS riêng (khi app bật GPS) + quét màn hình lấy giới hạn → Darwin notify `com.anlai97.speedpop.speed` (kèm chỉ số app) |
| SpringBoard | `src/hooks/SpringBoard.xm`, `src/SPPBubble.mm` | Nhận tốc độ, vẽ bong bóng trên cửa sổ riêng (màn xe nếu có CarPlay, ngược lại iPhone) |
| CarPlay (`com.apple.CarPlayApp`) | `src/hooks/CarPlay.xm` | Chạm bong bóng trên xe → mở đúng app qua `DBDashboard handleEvent:` |

Log: `/var/mobile/Documents/SpeedPop.log` (xem bằng Filza).

## Build

Không cần Theos trên máy: push lên GitHub, workflow `.github/workflows/build.yml` build trên macOS và đưa file `.deb` vào mục Artifacts của lần chạy.

Nếu đang cài CarDuo thì tắt bong bóng tốc độ trong Cài đặt CarDuo để không bị 2 bong bóng.
