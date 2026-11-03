#include "flutter_window.h"

#include <cctype>
#include <charconv>
#include <fstream>
#include <optional>
#include <string>
#include <system_error>

#include <flutter/standard_method_codec.h>
#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Devices.Enumeration.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/base.h>

#include "flutter/generated_plugin_registrant.h"

namespace {

using flutter::EncodableValue;
using PairingMethodResult = flutter::MethodResult<EncodableValue>;
using winrt::Windows::Devices::Bluetooth::BluetoothLEDevice;
using winrt::Windows::Devices::Enumeration::DevicePairingKinds;
using winrt::Windows::Devices::Enumeration::DevicePairingProtectionLevel;
using winrt::Windows::Devices::Enumeration::DevicePairingResultStatus;

constexpr char kPairingChannel[] = "neolink/windows_pairing";

std::string DiagnosticLogPath() {
  char temporary_directory[MAX_PATH + 1] = {};
  const DWORD length =
      GetTempPathA(static_cast<DWORD>(sizeof(temporary_directory)),
                   temporary_directory);
  if (length == 0 || length >= sizeof(temporary_directory)) {
    return "neolink_desktop.log";
  }
  return std::string(temporary_directory, length) + "neolink_desktop.log";
}

void AppendDiagnosticLog(const std::string& line) {
  std::ofstream stream(DiagnosticLogPath(), std::ios::app);
  stream << line << '\n';
}

std::optional<uint64_t> ParseBluetoothAddress(const std::string& device_id) {
  std::string hex;
  hex.reserve(12);
  for (const unsigned char character : device_id) {
    if (std::isxdigit(character)) {
      hex.push_back(static_cast<char>(character));
    }
  }
  if (hex.size() != 12) {
    return std::nullopt;
  }

  uint64_t address = 0;
  const char* end = hex.data() + hex.size();
  const auto parsed = std::from_chars(hex.data(), end, address, 16);
  if (parsed.ec != std::errc{} || parsed.ptr != end) {
    return std::nullopt;
  }
  return address;
}

// DevicePairingResultStatus 的枚举值在 Flutter 支持的各 Windows SDK 之间
// 保持稳定。按数值翻译成名称，使旧 SDK 构建下的失败日志仍可读。
std::string PairingStatusName(DevicePairingResultStatus status) {
  switch (static_cast<int32_t>(status)) {
    case 0:
      return "Paired";
    case 1:
      return "NotReadyToPair";
    case 2:
      return "NotPaired";
    case 3:
      return "AlreadyPaired";
    case 4:
      return "ConnectionRejected";
    case 5:
      return "TooManyConnections";
    case 6:
      return "HardwareFailure";
    case 7:
      return "AuthenticationTimeout";
    case 8:
      return "AuthenticationNotAllowed";
    case 9:
      return "AuthenticationFailure";
    case 10:
      return "NoSupportedProfiles";
    case 11:
      return "ProtectionLevelCouldNotBeMet";
    case 12:
      return "AccessDenied";
    case 13:
      return "InvalidCeremonyData";
    case 14:
      return "PairingCanceled";
    case 15:
      return "OperationAlreadyInProgress";
    case 16:
      return "RequiredHandlerNotRegistered";
    case 17:
      return "RejectedByHandler";
    case 18:
      return "RemoteDeviceHasAssociation";
    case 19:
      return "Failed";
    default:
      return "Unknown(" + std::to_string(static_cast<int32_t>(status)) + ")";
  }
}

winrt::fire_and_forget PairBluetoothDevice(
    std::string device_id,
    std::unique_ptr<PairingMethodResult> method_result) {
  try {
    const auto address = ParseBluetoothAddress(device_id);
    if (!address.has_value()) {
      method_result->Error("invalid-address",
                           "Expected a 48-bit Bluetooth address: " + device_id);
      co_return;
    }

    const BluetoothLEDevice device =
        co_await BluetoothLEDevice::FromBluetoothAddressAsync(*address);
    if (!device) {
      method_result->Error("device-not-found",
                           "Windows could not resolve the Bluetooth device");
      co_return;
    }

    const auto pairing = device.DeviceInformation().Pairing();
    if (pairing.IsPaired()) {
      method_result->Success(EncodableValue("AlreadyPaired"));
      co_return;
    }
    if (!pairing.CanPair()) {
      method_result->Error("not-pairable",
                           "Windows reports that the device cannot be paired");
      co_return;
    }

    // 通用 PairAsync 路径在 Windows 10 下可能协商出
    // EncryptionAndAuthentication，无输入输出能力的 Just Works 外设无法
    // 满足。这里精确请求 CT-Prov 设备实现的配对种类与保护等级，并显式
    // 接受 ConfirmOnly 事件。
    const auto custom_pairing = pairing.Custom();
    const auto pairing_requested_revoker = custom_pairing.PairingRequested(
        winrt::auto_revoke,
        [](const auto&, const auto& event_args) { event_args.Accept(); });
    const auto result = co_await custom_pairing.PairAsync(
        DevicePairingKinds::ConfirmOnly,
        DevicePairingProtectionLevel::Encryption);
    const auto status = result.Status();
    const auto status_name = PairingStatusName(status);
    if (status == DevicePairingResultStatus::Paired ||
        status == DevicePairingResultStatus::AlreadyPaired) {
      method_result->Success(
          EncodableValue("CustomPairAsync/" + status_name));
      co_return;
    }

    method_result->Error(
        "pair-failed",
        "Windows CustomPairAsync(ConfirmOnly, Encryption) status: " +
            status_name,
        EncodableValue(static_cast<int32_t>(status)));
  } catch (const winrt::hresult_error& error) {
    method_result->Error(
        "pair-exception", winrt::to_string(error.message()),
        EncodableValue(static_cast<int64_t>(error.code().value)));
  } catch (const std::exception& error) {
    method_result->Error("pair-exception", error.what());
  }
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  // 每次启动清空执行转录日志，便于远程排障时读取最近一次完整过程。
  std::ofstream(DiagnosticLogPath(), std::ios::trunc).close();

  pairing_channel_ =
      std::make_unique<flutter::MethodChannel<EncodableValue>>(
          flutter_controller_->engine()->messenger(), kPairingChannel,
          &flutter::StandardMethodCodec::GetInstance());
  pairing_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<EncodableValue>& call,
         std::unique_ptr<PairingMethodResult> result) {
        if (call.method_name() == "log") {
          const auto* line = std::get_if<std::string>(call.arguments());
          if (line == nullptr) {
            result->Error("invalid-arguments", "log expects a string");
            return;
          }
          AppendDiagnosticLog(*line);
          result->Success();
          return;
        }
        if (call.method_name() != "pair") {
          result->NotImplemented();
          return;
        }
        const auto* device_id =
            std::get_if<std::string>(call.arguments());
        if (device_id == nullptr) {
          result->Error("invalid-arguments", "pair expects a device ID string");
          return;
        }
        PairBluetoothDevice(*device_id, std::move(result));
      });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  pairing_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
