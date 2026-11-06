#pragma once
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <shobjidl.h>
#include <shellapi.h>
#include <wincred.h>
#include <dwmapi.h>
#include <string>
#include <vector>
#include <memory>

class SpaceDesktopChannel {
 public:
  explicit SpaceDesktopChannel(flutter::BinaryMessenger* messenger, HWND window)
      : window_(window) {
    channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        messenger, "com.cers.space/desktop", &flutter::StandardMethodCodec::GetInstance());
    channel_->SetMethodCallHandler([this](const auto& call, auto result) { Handle(call, std::move(result)); });
  }
  bool dirty = false;
  void NotifySystemAppearance() {
    channel_->InvokeMethod("systemAppearanceChanged", std::make_unique<flutter::EncodableValue>());
  }
 private:
  HWND window_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  static std::wstring wide(const std::string& text) {
    if (text.empty()) return {};
    int n=MultiByteToWideChar(CP_UTF8,0,text.c_str(),static_cast<int>(text.size()),nullptr,0);
    std::wstring out(n,0);MultiByteToWideChar(CP_UTF8,0,text.c_str(),static_cast<int>(text.size()),out.data(),n);return out;
  }
  static std::string utf8(const std::wstring& text) {
    if(text.empty())return {};
    int n=WideCharToMultiByte(CP_UTF8,0,text.c_str(),static_cast<int>(text.size()),nullptr,0,nullptr,nullptr);
    std::string out(n,0);WideCharToMultiByte(CP_UTF8,0,text.c_str(),static_cast<int>(text.size()),out.data(),n,nullptr,nullptr);return out;
  }
  void Handle(const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    using V=flutter::EncodableValue;using M=flutter::EncodableMap;using L=flutter::EncodableList;
    const auto* args=call.arguments()?std::get_if<M>(call.arguments()):nullptr;
    auto text=[&](const char* key)->std::string{if(!args)return {};auto it=args->find(V(key));return it!=args->end()&&std::holds_alternative<std::string>(it->second)?std::get<std::string>(it->second):std::string();};
    auto boolean=[&](const char* key)->bool{if(!args)return false;auto it=args->find(V(key));return it!=args->end()&&std::holds_alternative<bool>(it->second)&&std::get<bool>(it->second);};
    const std::string method=call.method_name();
    if(method=="diagnostics"){RECT r{};GetWindowRect(window_,&r);wchar_t title[256]{};GetWindowTextW(window_,title,256);result->Success(V(M{{V("title"),V(utf8(title))},{V("frameWidth"),V(static_cast<int32_t>(r.right-r.left))},{V("frameHeight"),V(static_cast<int32_t>(r.bottom-r.top))},{V("dpi"),V(static_cast<int32_t>(GetDpiForWindow(window_)))}}));return;}
    if(method=="accessibility"){
      BOOL animations=TRUE;SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION,0,&animations,0);
      DWORD transparency=1,size=sizeof(DWORD);HKEY key=nullptr;
      if(RegOpenKeyExW(HKEY_CURRENT_USER,L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",0,KEY_READ,&key)==ERROR_SUCCESS){RegQueryValueExW(key,L"EnableTransparency",nullptr,nullptr,reinterpret_cast<LPBYTE>(&transparency),&size);RegCloseKey(key);}
      result->Success(V(M{{V("reduceMotion"),V(animations==FALSE)},{V("reduceTransparency"),V(transparency==0)}}));return;
    }
    if(method=="dirty"){dirty=boolean("dirty");result->Success();return;}
    if(method=="appearance"){BOOL dark=boolean("dark");DwmSetWindowAttribute(window_,20,&dark,sizeof(dark));result->Success();return;}
    if(method=="systemAppearance"){
      DWORD light=1,size=sizeof(DWORD);HKEY key=nullptr;
      if(RegOpenKeyExW(HKEY_CURRENT_USER,L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",0,KEY_READ,&key)==ERROR_SUCCESS){RegQueryValueExW(key,L"AppsUseLightTheme",nullptr,nullptr,reinterpret_cast<LPBYTE>(&light),&size);RegCloseKey(key);}
      result->Success(V(light==0));return;
    }
    if(method=="appInfo"){result->Success(V(M{{V("version"),V(FLUTTER_VERSION)},{V("build"),V(std::to_string(FLUTTER_VERSION_BUILD))}}));return;}
    if(method=="openExternal"){
      const auto url=text("url");if(url.rfind("https://",0)!=0&&url.rfind("mailto:",0)!=0){result->Success(V(false));return;}
      auto value=wide(url);auto opened=ShellExecuteW(window_,L"open",value.c_str(),nullptr,nullptr,SW_SHOWNORMAL);
      result->Success(V(reinterpret_cast<INT_PTR>(opened)>32));return;
    }
    if(method=="openFiles"){
      IFileOpenDialog* dialog=nullptr;L files;
      if(SUCCEEDED(CoCreateInstance(CLSID_FileOpenDialog,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&dialog)))){
        DWORD options=FOS_FILEMUSTEXIST|FOS_PATHMUSTEXIST|FOS_FORCEFILESYSTEM;
        if(boolean("multiple"))options|=FOS_ALLOWMULTISELECT;
        dialog->SetOptions(options);dialog->SetTitle(L"选择文件");
        if(boolean("sqliteOnly")){const COMDLG_FILTERSPEC filters[]={{L"SQLite 数据库",L"*.sqlite;*.sqlite3;*.db"}};dialog->SetFileTypes(1,filters);}
        if(SUCCEEDED(dialog->Show(window_))){IShellItemArray* items=nullptr;if(SUCCEEDED(dialog->GetResults(&items))){DWORD count=0;items->GetCount(&count);for(DWORD i=0;i<count;i++){IShellItem* item=nullptr;if(SUCCEEDED(items->GetItemAt(i,&item))){PWSTR path=nullptr;if(SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH,&path))){files.emplace_back(utf8(path));CoTaskMemFree(path);}item->Release();}}items->Release();}}
        dialog->Release();
      }result->Success(V(files));return;
    }
    if(method=="saveFile"){
      IFileSaveDialog* dialog=nullptr;std::string path;
      if(SUCCEEDED(CoCreateInstance(CLSID_FileSaveDialog,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&dialog)))){
        dialog->SetOptions(FOS_OVERWRITEPROMPT|FOS_FORCEFILESYSTEM|FOS_PATHMUSTEXIST);dialog->SetFileName(wide(text("name")).c_str());
        if(SUCCEEDED(dialog->Show(window_))){IShellItem* item=nullptr;if(SUCCEEDED(dialog->GetResult(&item))){PWSTR value=nullptr;if(SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH,&value))){path=utf8(value);CoTaskMemFree(value);}item->Release();}}dialog->Release();
      }if(path.empty())result->Success();else result->Success(V(path));return;
    }
    if(method=="preview"||method=="reveal"){
      auto path=wide(text("path"));if(method=="preview")ShellExecuteW(window_,L"open",path.c_str(),nullptr,nullptr,SW_SHOWNORMAL);
      else{auto command=L"/select,\""+path+L"\"";ShellExecuteW(window_,L"open",L"explorer.exe",command.c_str(),nullptr,SW_SHOWNORMAL);}result->Success();return;
    }
    if(method=="readSecret"||method=="writeSecret"){
      const auto name=wide("SpaceFlutter:"+text("id"));
      if(method=="readSecret"){
        PCREDENTIALW credential=nullptr;if(CredReadW(name.c_str(),CRED_TYPE_GENERIC,0,&credential)){
          std::string value(reinterpret_cast<char*>(credential->CredentialBlob),credential->CredentialBlobSize);CredFree(credential);result->Success(V(value));
        }else if(GetLastError()==ERROR_NOT_FOUND){result->Success();}else{result->Error("credential","无法读取Windows凭据管理器");}
      }else{
        auto value=text("value");CREDENTIALW credential{};credential.Type=CRED_TYPE_GENERIC;credential.TargetName=const_cast<wchar_t*>(name.c_str());credential.Persist=CRED_PERSIST_LOCAL_MACHINE;credential.CredentialBlobSize=static_cast<DWORD>(value.size());credential.CredentialBlob=reinterpret_cast<LPBYTE>(value.data());
        if(CredWriteW(&credential,0))result->Success();else result->Error("credential","无法保存Windows凭据");
      }return;
    }
    if(method=="clipboardFiles"){
      L files;if(OpenClipboard(window_)){auto data=GetClipboardData(CF_HDROP);if(data){auto drop=reinterpret_cast<HDROP>(data);const UINT count=DragQueryFileW(drop,0xffffffff,nullptr,0);for(UINT i=0;i<count;i++){const UINT len=DragQueryFileW(drop,i,nullptr,0);std::wstring file(len+1,0);DragQueryFileW(drop,i,file.data(),len+1);file.resize(len);files.emplace_back(utf8(file));}}CloseClipboard();}result->Success(V(files));return;
    }
    if(method=="clipboardImage"){
      std::vector<uint8_t> image;if(OpenClipboard(window_)){const auto format=RegisterClipboardFormatW(L"PNG");auto data=GetClipboardData(format);if(data){const SIZE_T size=GlobalSize(data);const auto* ptr=static_cast<const uint8_t*>(GlobalLock(data));if(ptr&&size<=10*1024*1024){image.assign(ptr,ptr+size);}if(ptr)GlobalUnlock(data);}CloseClipboard();}
      if(image.empty())result->Success();else result->Success(V(image));return;
    }
    result->NotImplemented();
  }
};
