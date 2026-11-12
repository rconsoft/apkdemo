# MyGym Workspace — Native Flutter app

This is the dedicated MyGym Workspace Android project location (separate from the CRM app).

**Display name:** MyGym Workspace  
**Laravel API:** https://mygym.rconsoft.com/api/v1  
**Android package:** com.rconsoft.mygymworkspace

## Upload Flutter source archive
Place the supplied `MYGYM_WORKSPACE_GITHUB_SOURCE.tar.xz` file here and rename it to `flutter_source.tar.xz`. It contains the Flutter native source in `flutter_app/` and no server credentials.

## Build and download APK
GitHub → Actions → **Build MyGym Workspace Native Flutter APK** → **Run workflow**. After a successful run, download the artifact **MyGym_Workspace_APK**.

The website backend needs the accompanying **RCONSOFT_GYM_CLOUD_V13_WITH_MOBILE_API.zip**, and the **RCONSOFT_MOBILE_API_MASTER_TABLE.sql** must be imported into the master DB first.

This app is native Flutter, not WebView. Core features include token login by role, owner gyms list, gym dashboard, members, member payment entry, attendance and per-gym UPI QR settings. Other Laravel CMS screens remain web-only pending additional native implementation.
