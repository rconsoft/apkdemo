import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

const site = 'https://myhrms.rconsoft.com';
const navy = Color(0xFF101B35);
const royal = Color(0xFF3867F4);
const pale = Color(0xFFF4F7FB);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RconsoftApp());
}

class RconsoftApp extends StatelessWidget {
  const RconsoftApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title:'RCONSOFT HRMS + CRM',
    debugShowCheckedModeBanner:false,
    theme:ThemeData(
      useMaterial3:true,
      scaffoldBackgroundColor:pale,
      colorScheme:ColorScheme.fromSeed(seedColor:royal),
      appBarTheme:const AppBarTheme(backgroundColor:navy,foregroundColor:Colors.white)),
    home:const HrmsHome(),
  );
}

class Shortcut {
  final String name,path;
  final IconData icon;
  const Shortcut(this.name,this.path,this.icon);
}

const companyMenu=<Shortcut>[
  Shortcut('Dashboard','/dashboard',Icons.dashboard_outlined),
  Shortcut('Employees','/employees',Icons.groups),
  Shortcut('Employee Birthdays','/birthdays',Icons.cake_outlined),
  Shortcut('Attendance','/attendance',Icons.fact_check_outlined),
  Shortcut('Leave Management','/leaves',Icons.event_available_outlined),
  Shortcut('CRM & Leads','/leads',Icons.filter_alt_outlined),
  Shortcut('Tasks & Projects','/tasks',Icons.task_alt_outlined),
  Shortcut('Plans & Billing','/billing',Icons.credit_card_outlined),
  Shortcut('Reports','/reports',Icons.bar_chart_outlined),
  Shortcut('My Profile','/profile',Icons.person_outline),
];
const staffMenu=<Shortcut>[
  Shortcut('My Dashboard','/employee/dashboard',Icons.dashboard_outlined),
  Shortcut('My Attendance','/employee/attendance',Icons.fact_check_outlined),
  Shortcut('My Performance','/employee/performance',Icons.assessment_outlined),
  Shortcut('Change Password','/employee/change-password',Icons.lock_outline),
  Shortcut('Plans & Billing','/billing',Icons.credit_card_outlined),
];
const platformMenu=<Shortcut>[
  Shortcut('Super Admin Dashboard','/rconsoft',Icons.dashboard_outlined),
  Shortcut('All Tenants & Approvals','/rconsoft',Icons.apartment_outlined),
  Shortcut('Create New Tenant','/rconsoft/tenants/create',Icons.add_business_outlined),
];

class HrmsHome extends StatefulWidget {
  const HrmsHome({super.key});
  @override
  State<HrmsHome> createState()=>_HrmsHomeState();
}

class _HrmsHomeState extends State<HrmsHome> {
  final scaffoldKey=GlobalKey<ScaffoldState>();
  late final WebViewController web;
  bool started=false,waiting=false,hasError=false;
  int progress=0;
  String path='/login',role='guest',error='';
  bool get signedIn => role!='guest';
  List<Shortcut> get menu=>role=='platform'?platformMenu:role=='staff'?staffMenu:companyMenu;
  List<Shortcut> get bottom=>role=='platform'
      ? [platformMenu[0],platformMenu[2],const Shortcut('More','_menu',Icons.menu)]
      : role=='staff'
      ? [staffMenu[0],staffMenu[1],staffMenu[2],const Shortcut('More','_menu',Icons.menu)]
      : [companyMenu[0],companyMenu[1],companyMenu[5],const Shortcut('More','_menu',Icons.menu)];

  @override
  void initState(){
    super.initState();
    web=WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress:(p){if(mounted)setState(()=>progress=p);},
        onPageStarted:(url){
          if(!mounted)return;
          setState((){
            started=true;waiting=true;hasError=false;
            identify(url);
          });
        },
        onPageFinished:(url){
          if(!mounted)return;
          setState((){
            waiting=false;hasError=false;
            identify(url);
          });
        },
        onWebResourceError:(e){
          if(e.isForMainFrame!=true || !mounted)return;
          setState((){
            waiting=false;hasError=true;error=e.description;
          });
        },
        onNavigationRequest:(r){
          final uri=Uri.tryParse(r.url);
          if(uri==null)return NavigationDecision.prevent;
          if(uri.scheme=='https'&&uri.host=='myhrms.rconsoft.com'){
            return NavigationDecision.navigate;
          }
          if(['https','http','tel','mailto','sms'].contains(uri.scheme)){
            launchUrl(uri,mode:LaunchMode.externalApplication);
          }
          return NavigationDecision.prevent;
        },
      ));
  }

  void identify(String value){
    final url=Uri.tryParse(value);
    if(url==null || url.host!='myhrms.rconsoft.com')return;
    path=url.path;
    if(path=='/login'){role='guest';}
    else if(path.startsWith('/rconsoft')){role='platform';}
    else if(path.startsWith('/employee')){role='staff';}
    else if(['dashboard','employees','birthdays','attendance','leaves','leads','tasks','reports','profile']
        .any((p)=>path=='/'+p || path.startsWith('/'+p+'/'))){
      role='company';
    }
  }

  Future<void> go(String target) async{
    if(target=='_menu'){scaffoldKey.currentState?.openDrawer();return;}
    setState((){
      started=true;waiting=true;hasError=false;
    });
    await web.loadRequest(Uri.parse(site+target));
  }

  Future<void> reload()async{
    if(!started){await go('/login');return;}
    setState((){waiting=true;hasError=false;});
    await web.reload();
  }

  Future<void> back()async{
    if(started&&await web.canGoBack()){await web.goBack();return;}
    setState((){started=false;role='guest';});
  }

  Future<void> chrome()async{
    final current=started?await web.currentUrl():site+'/login';
    if(current!=null){
      await launchUrl(Uri.parse(current),mode:LaunchMode.externalApplication);
    }
  }

  int get tabIndex {
    final tabs=bottom;
    for(int i=0;i<tabs.length-1;i++){
      final p=tabs[i].path;
      if(path==p || path.startsWith(p+'/'))return i;
    }
    return tabs.length-1;
  }

  String get subheading=>role=='platform'?'Super Admin Control Center':
    role=='staff'?'Employee Portal':
    role=='company'?'Company Workspace':'HRMS + CRM PRO';

  @override
  Widget build(BuildContext context)=>PopScope(
    canPop:false,
    onPopInvokedWithResult:(didPop,result){
      if(!didPop)back();
    },
    child:Scaffold(
      key:scaffoldKey,
      appBar:AppBar(
        leading:started?IconButton(icon:const Icon(Icons.arrow_back),
          tooltip:'Back',onPressed:back):null,
        title:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          const Text('RCONSOFT',style:TextStyle(fontWeight:FontWeight.w900,
            letterSpacing:1.3,fontSize:18)),
          Text(subheading,style:const TextStyle(fontSize:11,color:Colors.white70)),
        ]),
        actions:[
          if(started&&signedIn)IconButton(
            onPressed:()=>scaffoldKey.currentState?.openDrawer(),
            icon:const Icon(Icons.menu),tooltip:'All HRMS Modules'),
          if(started)IconButton(onPressed:reload,icon:const Icon(Icons.refresh),
            tooltip:'Refresh'),
          PopupMenuButton<String>(
            icon:const Icon(Icons.more_vert),
            itemBuilder:(_)=>const [
              PopupMenuItem(value:'home',child:Text('HRMS Website Home')),
              PopupMenuItem(value:'chrome',child:Text('Open in Chrome')),
              PopupMenuItem(value:'login',child:Text('Open Login')),
            ],
            onSelected:(v){
              if(v=='home')go('/');
              if(v=='chrome')chrome();
              if(v=='login')go('/login');
            },
          ),
        ],
      ),
      drawer:started&&signedIn?Drawer(
        child:SafeArea(child:ListView(children:[
          Container(color:navy,padding:const EdgeInsets.all(22),
            child:const Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text('RCONSOFT',style:TextStyle(color:Colors.white,
                fontSize:24,fontWeight:FontWeight.w900)),
              SizedBox(height:6),
              Text('HRMS + CRM PRO',style:TextStyle(color:Colors.white70)),
            ])),
          ...menu.map((link)=>ListTile(
            leading:Icon(link.icon,color:navy),
            title:Text(link.name),
            selected:path==link.path,
            onTap:(){
              Navigator.pop(context);
              go(link.path);
            },
          )),
          const Divider(),
          ListTile(leading:const Icon(Icons.open_in_browser),
            title:const Text('Open in Chrome'),
            onTap:(){Navigator.pop(context);chrome();}),
        ])),
      ):null,
      body:SafeArea(child:Column(children:[
        if(started&&waiting)LinearProgressIndicator(
          value:progress<95?progress/100:null,minHeight:3),
        Expanded(child:!started?welcome():Stack(children:[
          WebViewWidget(controller:web),
          if(hasError)Container(color:pale,child:Center(child:Padding(
            padding:const EdgeInsets.all(22),
            child:Column(mainAxisSize:MainAxisSize.min,children:[
              const Icon(Icons.wifi_off,size:48,color:navy),
              const SizedBox(height:12),
              const Text('HRMS website not reachable',
                style:TextStyle(fontWeight:FontWeight.bold,fontSize:19)),
              const SizedBox(height:10),
              Text(error,textAlign:TextAlign.center),
              const SizedBox(height:18),
              FilledButton.icon(onPressed:reload,
                icon:const Icon(Icons.refresh),label:const Text('Retry')),
              TextButton(onPressed:chrome,child:const Text('Open in Chrome')),
            ]),
          ))),
        ])),
      ])),
      bottomNavigationBar:started&&signedIn?NavigationBar(
        selectedIndex:tabIndex,
        onDestinationSelected:(i)=>go(bottom[i].path),
        destinations:bottom.map((item)=>NavigationDestination(
          icon:Icon(item.icon),label:item.name=='CRM & Leads'?'CRM':
            item.name=='Super Admin Dashboard'?'Home':
            item.name=='Create New Tenant'?'New Tenant':
            item.name=='My Dashboard'?'Home':
            item.name=='Employee Birthdays'?'Birthdays':item.name,
        )).toList(),
      ):null,
    ),
  );

  Widget welcome()=>Center(child:SingleChildScrollView(
    padding:const EdgeInsets.all(24),
    child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:460),
      child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        const CircleAvatar(radius:44,backgroundColor:navy,
          child:Icon(Icons.business_center,size:43,color:Colors.white)),
        const SizedBox(height:22),
        const Text('Full HRMS + CRM',textAlign:TextAlign.center,
          style:TextStyle(fontSize:28,fontWeight:FontWeight.w900,color:navy)),
        const SizedBox(height:9),
        const Text('Original Laravel HRMS screens inside Flutter. Same login, forms, permissions and live company database.',
          textAlign:TextAlign.center,
          style:TextStyle(color:Color(0xFF667892),height:1.5)),
        const SizedBox(height:26),
        FilledButton.icon(
          style:FilledButton.styleFrom(
            backgroundColor:royal,minimumSize:const Size(100,54)),
          onPressed:()=>go('/login'),icon:const Icon(Icons.login),
          label:const Text('Login with Email ID & Password')),
        const SizedBox(height:18),
        const Wrap(alignment:WrapAlignment.center,spacing:8,runSpacing:7,children:[
          Chip(label:Text('Employees')),Chip(label:Text('Attendance')),
          Chip(label:Text('Leaves')),Chip(label:Text('CRM Leads')),
          Chip(label:Text('Tasks')),Chip(label:Text('Reports')),
          Chip(label:Text('Super Admin')),Chip(label:Text('Billing')),
        ]),
        const SizedBox(height:14),
        const Text('Requires your live HRMS website and an internet connection.',
          textAlign:TextAlign.center,style:TextStyle(color:Color(0xFF667892))),
        const SizedBox(height:17),
        TextButton.icon(onPressed:chrome,
          icon:const Icon(Icons.open_in_browser),
          label:const Text('Open website in Chrome')),
      ])),
  ));
}
