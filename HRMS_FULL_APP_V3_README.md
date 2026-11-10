# RCONSOFT HRMS Full V3 – Flutter + Laravel

The original Laravel web pages are embedded in a Flutter Android WebView, not rewritten as native Flutter forms. This preserves the available website features via the existing Laravel session and tenant database.

The audited website includes company Dashboard, Employees (CRUD & employee accounts), Birthdays, Attendance, Leave Management, CRM Leads, Tasks & Projects, Plans & Billing, Reports (attendance CSV), Profile; employee Dashboard, Attendance, Performance, Password Change; and RCONSOFT Super Admin Dashboard, Tenant Creation/Management, DB Initialization and Subscription Approvals.

Login button opens the existing Laravel email and password form. Laravel decides Super Admin, Company Admin/Manager/HR or Employee destination and access. No direct MySQL access or database passwords in APK. All work remains on the existing website.

Requires https://myhrms.rconsoft.com to be online. New windows, CSV downloads, camera uploads, and third-party redirects may require opening the website in Chrome and have not been phone-tested. This is not a feature-by-feature native rewrite.

Build using GitHub Actions (.github/workflows/hrms-full-android.yml), or manually via flutter create --platforms=android --org com.rconsoft --project-name rconsoft_hrms_full . then flutter pub get and flutter build apk --release.
