import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(const CrmApp());

const crimson = Color(0xFFE53935);
const charcoal = Color(0xFF0B0B0F);
const panel = Color(0xFF19191F);
const statuses = ['new','contacted','qualified','proposal','negotiation','converted','lost'];

class Api {
  String base = 'https://myhrms.rconsoft.com/api/mobile/v1';
  String token = '';
  Future<dynamic> request(String route, {String method = 'GET', Map<String, dynamic>? data}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final uri = Uri.parse('${base.replaceAll(RegExp(r"/+$"), "")}$route');
      final request = await client.openUrl(method, uri);
      request.headers.contentType = ContentType.json;
      request.headers.set('Accept', 'application/json');
      if (token.isNotEmpty) request.headers.set('Authorization', 'Bearer $token');
      if (data != null) request.write(jsonEncode(data));
      final response = await request.close().timeout(const Duration(seconds: 25));
      final body = await utf8.decoder.bind(response).join();
      final decoded = body.isEmpty ? null : jsonDecode(body);
      if (response.statusCode >= 400) {
        String message = 'Server error ${response.statusCode}';
        if (decoded is Map && decoded['message'] != null) message = decoded['message'].toString();
        throw Exception(message);
      }
      return decoded;
    } finally { client.close(force: true); }
  }
}

class CrmApp extends StatefulWidget {
  const CrmApp({super.key});
  @override
  State<CrmApp> createState() => _CrmAppState();
}

class _CrmAppState extends State<CrmApp> {
  final api = Api();
  final navigatorKey = GlobalKey<NavigatorState>();
  String role = '';
  Map<String,dynamic> user = {};
  Map<String,dynamic> stats = {};
  List<Map<String,dynamic>> tenantList = [];
  List<Map<String,dynamic>> pendingRequests = [];
  List<Map<String,dynamic>> attendanceList = [];
  List<Map<String,dynamic>> leaveList = [];
  bool get isSuper => role == 'super_admin';
  bool get isManager => ['company_admin','admin','manager','hr'].contains(role);

  bool signedIn = false;
  bool demo = true;
  bool loading = false;
  int tab = 0;
  String username = 'Demo Employee';
  List<Map<String, dynamic>> leads = [];
  List<Map<String, dynamic>> hrmsTasks=[];
  List<Map<String, dynamic>> employees=[];
  final sample = [
    {'id': 1, 'name': 'Amit Sharma', 'company': 'Sharma Enterprises', 'phone': '9876543210', 'email': 'amit@example.com', 'location': 'Bhubaneswar', 'status': 'new', 'industry': 'Retail', 'domain': 'sharma.example', 'next_follow_up_at': '2026-11-07'},
    {'id': 2, 'name': 'Priya Das', 'company': 'Blue Ocean Travel', 'phone': '9000000000', 'email': '', 'location': 'Puri', 'status': 'contacted', 'industry': 'Travel', 'domain': '', 'next_follow_up_at': '2026-11-08'},
    {'id': 3, 'name': 'Rahul Mishra', 'company': 'Sunrise Hotel', 'phone': '9888888888', 'email': '', 'location': 'Cuttack', 'status': 'qualified', 'industry': 'Hospitality', 'domain': '', 'next_follow_up_at': ''},
    {'id': 4, 'name': 'Sneha Patra', 'company': 'Fit Life Gym', 'phone': '', 'email': '', 'location': 'Bhubaneswar', 'status': 'converted', 'industry': 'Fitness', 'domain': '', 'next_follow_up_at': ''},
  ];
  List<Map<String, dynamic>> activities = [];

  void notice(String msg) { if (mounted) ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(SnackBar(content: Text(msg))); }

  List<Map<String,dynamic>> asRows(dynamic input) {
    final d = input is Map ? input['data'] : input;
    return d is List ? d.map((x)=>Map<String,dynamic>.from(x as Map)).toList() : [];
  }

  Future<void> sync() async {
    if (demo || !signedIn) return;
    setState(()=>loading=true);
    try {
      final data=await api.request(isSuper?'/super-admin/dashboard':'/dashboard');
      final summary=data is Map?data['summary']:null;
      stats=Map<String,dynamic>.from(summary is Map?summary:{});
      if(isSuper){
        final companies=await api.request('/super-admin/tenants');
        final requests=await api.request('/super-admin/subscriptions');
        if(mounted)setState(() {tenantList=asRows(companies);pendingRequests=asRows(requests);});
      } else {
        final tasks=await api.request('/tasks');
        final attendance=await api.request('/attendance');
        final leaves=await api.request('/leaves');
        List<Map<String,dynamic>> newLeads=[];
        List<Map<String,dynamic>> people=[];
        if(isManager){
          newLeads=asRows(await api.request('/leads')).map((x){
            x['company']=x['company_name']??'';
            final st=(x['stage']??'New').toString();
            x['status']=st=='Won'?'converted':st.toLowerCase();
            return x;
          }).toList();
          people=asRows(await api.request('/employees'));
        }
        if(mounted)setState((){
          hrmsTasks=asRows(tasks);attendanceList=asRows(attendance);
          leaveList=asRows(leaves);leads=newLeads;employees=people;
        });
      }
    }catch(e){notice('Sync error: $e');}
    finally{if(mounted)setState(()=>loading=false);}
  }


  Future<void> loginDialog() async {
    final email = TextEditingController();
    final pass = TextEditingController();
    await showDialog<void>(context: navigatorKey.currentContext!, builder: (ctx) => AlertDialog(
      backgroundColor: panel,
      title: const Text('Enter Login ID & Password'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        field(email, 'Email ID', icon: Icons.person_outline),
        const SizedBox(height: 10),
        TextField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock))),
        const SizedBox(height: 10),
        const Text('Your account role and company will be detected automatically.', style: TextStyle(fontSize: 12, color: Colors.white60)),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () async {
          if (email.text.trim().isEmpty || pass.text.isEmpty) { notice('Enter Email ID and Password'); return; }
          try {
            final answer = await api.request('/login', method: 'POST', data: {'email': email.text.trim(), 'password': pass.text});
            api.token = answer['token'].toString();
            if (api.token.isEmpty) throw Exception('No token returned');
            user = Map<String,dynamic>.from(answer['user'] as Map);
            role = (user['role'] ?? 'employee').toString();
            if(!['super_admin','company_admin','admin','manager','hr','employee'].contains(role)) throw Exception('Unsupported role');
            demo = false;
            username = (user['name'] ?? 'Employee').toString();
            if (ctx.mounted) Navigator.pop(ctx);
            setState(() { signedIn = true; tab = 0; });
            await sync();
          } catch (e) { notice('Login failed: $e'); }
        }, child: const Text('Sign in'))
      ],
    ));
    email.dispose(); pass.dispose();
  }

  Widget field(TextEditingController controller, String label, {IconData? icon}) => TextField(
    controller: controller,
    decoration: InputDecoration(labelText: label, prefixIcon: icon == null ? null : Icon(icon), border: const OutlineInputBorder()),
  );

  Future<void> saveLead(Map<String, dynamic>? current) async {
    final name = TextEditingController(text: current?['name']?.toString() ?? '');
    final company = TextEditingController(text: current?['company']?.toString() ?? '');
    final phone = TextEditingController(text: current?['phone']?.toString() ?? '');
    final email = TextEditingController(text: current?['email']?.toString() ?? '');
    final location = TextEditingController(text: current?['location']?.toString() ?? '');
    final domain = TextEditingController(text: current?['domain']?.toString() ?? '');
    final industry = TextEditingController(text: current?['industry']?.toString() ?? '');
    String status = current?['status']?.toString() ?? 'new';
    await showDialog<void>(context: navigatorKey.currentContext!, builder: (ctx) => StatefulBuilder(builder: (ctx, change) => AlertDialog(
      backgroundColor: panel,
      title: Text(current == null ? 'Add new lead' : 'Edit lead'),
      content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        field(name, 'Client name *'), const SizedBox(height: 9),
        field(company, 'Company'), const SizedBox(height: 9),
        field(phone, 'Phone'), const SizedBox(height: 9),
        field(email, 'Email'), const SizedBox(height: 9),
        field(location, 'Location'), const SizedBox(height: 9),
        field(domain, 'Domain'), const SizedBox(height: 9),
        field(industry, 'Industry'), const SizedBox(height: 9),
        DropdownButtonFormField<String>(value: statuses.contains(status) ? status : 'new', decoration: const InputDecoration(labelText: 'Status'), items: statuses.map((s) => DropdownMenuItem(value: s, child: Text(s.toUpperCase()))).toList(), onChanged: (v) => change(() => status = v ?? 'new')),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () async {
          if (name.text.trim().isEmpty) { notice('Enter client name'); return; }
          final data = {'name': name.text.trim(), 'company': company.text.trim(), 'phone': phone.text.trim(), 'email': email.text.trim(), 'location': location.text.trim(), 'domain': domain.text.trim(), 'industry': industry.text.trim(), 'status': status};
          try {
            if (demo) {
              setState(() {
                if (current == null) {
                  leads.insert(0, {'id': DateTime.now().millisecondsSinceEpoch, ...data});
                } else {
                  leads[leads.indexWhere((l) => l['id'] == current['id'])] = {...current, ...data};
                }
              });
            } else {
              final stage=status=='converted'?'Won':status[0].toUpperCase()+status.substring(1);
              await api.request(current==null?'/leads':'/leads/${current['id']}',method:current==null?'POST':'PATCH',data:{
                'name':name.text.trim(),'company_name':company.text.trim(),
                'phone':phone.text.trim().isEmpty?null:phone.text.trim(),
                'email':email.text.trim().isEmpty?null:email.text.trim(),
                'stage':stage,'value':0,
              });
              await sync();
            }
            if (ctx.mounted) Navigator.pop(ctx);
            notice('Lead saved successfully');
          } catch (e) { notice('Save failed: $e'); }
        }, child: const Text('Save')),
      ],
    )));
    name.dispose(); company.dispose(); phone.dispose(); email.dispose(); location.dispose(); domain.dispose(); industry.dispose();
  }

  Future<void> activityDialog(Map<String, dynamic> lead) async {
    final note = TextEditingController();
    String channel = 'call';
    await showDialog<void>(context: navigatorKey.currentContext!, builder: (ctx) => StatefulBuilder(builder: (ctx, change) => AlertDialog(
      backgroundColor: panel,
      title: Text('Activity • ${lead['name']}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(value: channel, items: ['call','whatsapp','email','sms','meeting','note'].map((s) => DropdownMenuItem(value: s, child: Text(s.toUpperCase()))).toList(), onChanged: (v) => change(() => channel = v ?? 'call')),
        const SizedBox(height: 12),
        TextField(controller: note, maxLines: 3, decoration: const InputDecoration(labelText: 'Follow-up notes', border: OutlineInputBorder())),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () async {
          try {
            if (!demo) await api.request('/leads/${lead['id']}',method:'PATCH',data:{
              'name':lead['name'],'stage':lead['status']=='converted'?'Won':
                lead['status'].toString()[0].toUpperCase()+lead['status'].toString().substring(1),
              'notes':'${channel.toUpperCase()}: ${note.text.trim()}',
            });
            setState(() => activities.insert(0, {'channel': channel, 'note': note.text.trim(), 'lead_name': lead['name'], 'date': DateTime.now().toLocal().toString().substring(0,16)}));
            if (ctx.mounted) Navigator.pop(ctx);
            notice('Activity recorded');
          } catch (e) { notice('Activity failed: $e'); }
        }, child: const Text('Save')),
      ],
    )));
    note.dispose();
  }

  Future<void> deleteLead(Map<String, dynamic> lead) async {
    final ok = await showDialog<bool>(context: navigatorKey.currentContext!, builder: (ctx) => AlertDialog(
      title: const Text('Delete lead?'), content: Text('Remove ${lead['name']}? This cannot be undone.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: crimson)))],
    ));
    if (ok != true) return;
    try {
      if (!demo) { notice('Delete records from the HRMS website.'); return; }
      setState(() => leads.removeWhere((e) => e['id'] == lead['id']));
      notice('Lead deleted');
    } catch (e) { notice('Delete failed: $e'); }
  }

  Future<void> dial(String value, String scheme) async {
    if (value.trim().isEmpty) { notice('Phone number not available'); return; }
    final digits = value.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse(scheme == 'tel' ? 'tel:$digits' : 'https://wa.me/${digits.replaceAll('+', '')}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) notice('No app can open this link');
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: navigatorKey,
    title: 'RCONSOFT HRMS CRM', debugShowCheckedModeBanner: false,
    theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: charcoal, colorScheme: const ColorScheme.dark(primary: crimson, surface: panel), useMaterial3: true, cardTheme: const CardThemeData(color: panel, margin: EdgeInsets.symmetric(vertical: 6))),
    home: signedIn ? home() : welcome(),
  );

  Widget welcome() => Scaffold(body: SafeArea(child: Padding(padding: const EdgeInsets.all(24), child: Column(
    mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const CircleAvatar(radius: 44, backgroundColor: crimson, child: Icon(Icons.hub, size: 43, color: Colors.white)),
      const SizedBox(height: 26),
      const Text('RCONSOFT', textAlign: TextAlign.center, style: TextStyle(fontSize: 33, fontWeight: FontWeight.w900, letterSpacing: 3)),
      const Text('HRMS • CRM • TEAM TASKS', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60, letterSpacing: 2)),
      const SizedBox(height: 40),
      FilledButton.icon(onPressed: loginDialog, icon: const Icon(Icons.lock_open), label: const Padding(padding: EdgeInsets.all(12), child: Text('Employee Login'))),
      const SizedBox(height: 12),
      const SizedBox.shrink(),
      const SizedBox(height: 22),
      const Text('Login with your HRMS Email ID and Password. Your assigned workspace opens automatically.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.white54)),
    ],
  ))));


  Widget home(){
    final labels=isSuper?['Home','Tenants','Approvals','Profile']
      :isManager?['Home','Leads','Tasks','Team','Profile']
      :['Home','Attendance','Tasks','Leaves','Profile'];
    final icons=isSuper?[Icons.dashboard,Icons.apartment,Icons.verified_user,Icons.person]
      :isManager?[Icons.dashboard,Icons.people,Icons.checklist,Icons.badge,Icons.person]
      :[Icons.dashboard,Icons.schedule,Icons.checklist,Icons.event_note,Icons.person];
    final pages=isSuper?[dashboard(),tenantsPage(),approvalsPage(),profilePage()]
      :isManager?[dashboard(),leadsPage(),followupPage(),activityPage(),profilePage()]
      :[dashboard(),attendancePage(),followupPage(),leavesPage(),profilePage()];
    return Scaffold(
      appBar:AppBar(backgroundColor:charcoal,
        title:Row(children:[const Icon(Icons.hub,color:crimson),const SizedBox(width:10),
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            const Text('RCONSOFT',style:TextStyle(fontWeight:FontWeight.w900,letterSpacing:1)),
            Text(isSuper?'Super Admin':(user['company_name']??'HRMS CRM').toString(),
              maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:11,color:Colors.white60)),
          ]))]),
        actions:[IconButton(onPressed:sync,icon:const Icon(Icons.refresh))]),
      body:loading?const Center(child:CircularProgressIndicator()):
        SafeArea(child:pages[tab]),
      floatingActionButton:isManager&&tab==1?FloatingActionButton(
        backgroundColor:crimson,foregroundColor:Colors.white,
        onPressed:()=>saveLead(null),child:const Icon(Icons.add)):null,
      bottomNavigationBar:NavigationBar(selectedIndex:tab,backgroundColor:panel,
        indicatorColor:crimson.withValues(alpha:0.2),
        onDestinationSelected:(v)=>setState(()=>tab=v),
        destinations:List.generate(labels.length,(i)=>NavigationDestination(icon:Icon(icons[i]),label:labels[i]))),
    );
  }


  Widget section(String title, {Widget? extra}) => Row(children: [Expanded(child: Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold))), if (extra != null) extra]);
  Widget metric(String text, int value, IconData icon, Color color) => Container(
    decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white10)), padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: color, size: 25), const Spacer(), Text('$value', style: const TextStyle(fontSize: 27, fontWeight: FontWeight.bold)),
      Text(text, style: const TextStyle(fontSize: 12, color: Colors.white60)),
    ]),
  );


  Widget dashboard() => ListView(padding:const EdgeInsets.all(18),children:[
    Text('Welcome, $username',style:const TextStyle(fontSize:24,fontWeight:FontWeight.bold)),
    const SizedBox(height:4),
    Text(isSuper?'Platform overview':isManager?'Company dashboard':'Employee dashboard',
      style:const TextStyle(color:Colors.white60)),
    const SizedBox(height:22),
    GridView.builder(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),
      itemCount:stats.length,gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount:2,mainAxisSpacing:10,crossAxisSpacing:10,childAspectRatio:1.35),
      itemBuilder:(context,i){
        final item=stats.entries.elementAt(i);
        return metric(item.key.replaceAll('_',' ').toUpperCase(),
          int.tryParse(item.value.toString())??0,
          Icons.analytics_outlined,i.isEven?crimson:Colors.blueAccent);
      }),
    const SizedBox(height:20),
    Card(child:ListTile(leading:const Icon(Icons.shield_outlined,color:crimson),
      title:Text((user['company_name']??'RCONSOFT Platform').toString()),
      subtitle:Text('Role: $role'))),
    Card(child:ListTile(leading:const Icon(Icons.sync,color:crimson),
      title:const Text('Connected with Laravel / MySQL'),
      subtitle:const Text('Refresh to see latest website records'),
      trailing:IconButton(onPressed:sync,icon:const Icon(Icons.refresh)))),
  ]);


  Widget leadsPage() {
    return LeadsView(leads: leads, onEdit: saveLead, onActivity: activityDialog, onDelete: deleteLead, onCall: dial);
  }

  Widget followupPage()=>ListView(padding:const EdgeInsets.all(18),children:[
    section('Team tasks'),const SizedBox(height:12),
    if(hrmsTasks.isEmpty) const Card(child:ListTile(title:Text('No tasks yet'))),
    ...hrmsTasks.map((task)=>Card(child:ListTile(
      leading:const Icon(Icons.task_alt,color:crimson),
      title:Text((task['title']??'Task').toString()),
      subtitle:Text('${task['assigned_to']??'Unassigned'} • ${task['status']??'Open'}'),
      trailing:IconButton(icon:const Icon(Icons.done_all),tooltip:'Complete task',onPressed:()async{
        try{
          await api.request(isManager?'/tasks/${task['id']}':'/tasks/${task['id']}/my-status',
            method:'PATCH',data:isManager?{
            'title':task['title'],'priority':task['priority']??'Medium','status':'Completed',
            'description':task['description'],'assigned_to':task['assigned_to']}
            :{'status':'Completed'});
          await sync();notice('Task updated');
        }catch(e){notice('Task error: $e');}
      }),
    ))),
  ]);

  Widget activityPage()=>ListView(padding:const EdgeInsets.all(18),children:[
    section('Employees'),const SizedBox(height:12),
    if(employees.isEmpty) const Card(child:ListTile(title:Text('No employees found'))),
    ...employees.map((p)=>Card(child:ListTile(
      leading:const Icon(Icons.badge,color:crimson),
      title:Text('${p['first_name']??''} ${p['last_name']??''}'),
      subtitle:Text('${p['employee_code']??''} • ${p['department']??''}'),
    ))),
    const SizedBox(height:18),
    FilledButton.icon(onPressed:()async{
      try{
        final r=await api.request('/attendance');final list=r is Map?r['data']:r;
        if(!mounted)return;
        showModalBottomSheet(context:navigatorKey.currentContext!,builder:(ctx)=>ListView(children:[
          const ListTile(title:Text('Attendance history')),
          ...(list is List?list:[]).take(20).map((v)=>ListTile(
            title:Text((v['work_date']??'').toString()),
            subtitle:Text('Employee: ${v['employee_id']} • ${v['status']}'))),
        ]));
      }catch(e){notice('Attendance error: $e');}
    },icon:const Icon(Icons.schedule),label:const Text('Attendance history')),
  ]);


  Widget tenantsPage()=>ListView(padding:const EdgeInsets.all(18),children:[
    section('Company Workspaces'),const SizedBox(height:12),
    if(tenantList.isEmpty)const Card(child:ListTile(title:Text('No tenant records'))),
    ...tenantList.map((t)=>Card(child:ListTile(
      leading:const Icon(Icons.apartment,color:crimson),
      title:Text((t['name']??'Company').toString()),
      subtitle:Text('Slug: ${t['slug']??''}\nDatabase: ${t['database_ready_at']==null?'Pending':'Ready'}'),
      isThreeLine:true))),
  ]);

  Future<void> reviewRequest(Map<String,dynamic> r,String decision)async{
    try{
      await api.request('/super-admin/subscriptions/${r['id']}/review',
        method:'POST',data:{'decision':decision});
      notice('Subscription $decision');await sync();
    }catch(e){notice('Review error: $e');}
  }

  Widget approvalsPage()=>ListView(padding:const EdgeInsets.all(18),children:[
    section('Subscription Approvals'),const SizedBox(height:12),
    if(pendingRequests.isEmpty)const Card(child:ListTile(title:Text('No pending requests'))),
    ...pendingRequests.map((r)=>Card(child:Column(children:[
      ListTile(leading:const Icon(Icons.verified_user,color:crimson),
        title:Text((r['company']?['name']??'Company').toString()),
        subtitle:Text('${r['plan_months']??''} months • ${r['status']??''}')),
      Row(mainAxisAlignment:MainAxisAlignment.end,children:[
        TextButton(onPressed:()=>reviewRequest(r,'rejected'),child:const Text('Reject')),
        FilledButton(onPressed:()=>reviewRequest(r,'approved'),child:const Text('Approve')),
        const SizedBox(width:12)]),
    ]))),
  ]);

  Future<void> punch(String type)async{
    try{
      await api.request('/attendance/$type',method:'POST',data:{});
      notice(type=='check-in'?'Check-in recorded':'Check-out recorded');
      await sync();
    }catch(e){notice('Attendance error: $e');}
  }

  Widget attendancePage()=>ListView(padding:const EdgeInsets.all(18),children:[
    section('My Attendance'),const SizedBox(height:12),
    Row(children:[
      Expanded(child:FilledButton.icon(onPressed:()=>punch('check-in'),
        icon:const Icon(Icons.login),label:const Text('Check In'))),
      const SizedBox(width:8),
      Expanded(child:OutlinedButton.icon(onPressed:()=>punch('check-out'),
        icon:const Icon(Icons.logout),label:const Text('Check Out'))),
    ]),
    const SizedBox(height:15),
    if(attendanceList.isEmpty)const Card(child:ListTile(title:Text('No attendance yet'))),
    ...attendanceList.map((a)=>Card(child:ListTile(
      leading:const Icon(Icons.today,color:crimson),
      title:Text((a['work_date']??'').toString()),
      subtitle:Text('Status: ${a['status']??''} • In: ${a['check_in']??'—'}\nOut: ${a['check_out']??'—'}')))),
  ]);

  Widget leavesPage()=>ListView(padding:const EdgeInsets.all(18),children:[
    section('My Leaves'),const SizedBox(height:12),
    FilledButton.icon(onPressed:applyLeave,icon:const Icon(Icons.add),label:const Text('Apply for Leave')),
    const SizedBox(height:12),
    if(leaveList.isEmpty)const Card(child:ListTile(title:Text('No leave requests'))),
    ...leaveList.map((r)=>Card(child:ListTile(
      leading:const Icon(Icons.event_note,color:crimson),
      title:Text((r['leave_type']??'Leave').toString()),
      subtitle:Text('${r['start_date']} — ${r['end_date']}'),
      trailing:Text((r['status']??'').toString())))),
  ]);

  Future<void> applyLeave()async{
    final start=TextEditingController(),end=TextEditingController(),reason=TextEditingController();
    String type='Casual';
    await showDialog<void>(context:navigatorKey.currentContext!,builder:(ctx)=>StatefulBuilder(
      builder:(ctx,update)=>AlertDialog(
        title:const Text('Apply for Leave'),
        content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
          DropdownButtonFormField<String>(value:type,
            items:['Casual','Annual','Sick','Unpaid','Other']
              .map((s)=>DropdownMenuItem(value:s,child:Text(s))).toList(),
            onChanged:(v)=>update(()=>type=v??'Casual')),
          field(start,'Start YYYY-MM-DD'),field(end,'End YYYY-MM-DD'),field(reason,'Reason'),
        ])),
        actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),
          FilledButton(onPressed:()async{
            try{
              await api.request('/leaves',method:'POST',data:{
                'leave_type':type,'start_date':start.text.trim(),
                'end_date':end.text.trim(),'reason':reason.text.trim()});
              if(ctx.mounted)Navigator.pop(ctx);
              notice('Leave application submitted');await sync();
            }catch(e){notice('Leave failed: $e');}
          },child:const Text('Submit')),
        ],
      )));
    start.dispose();end.dispose();reason.dispose();
  }

  Widget profilePage() => ListView(padding: const EdgeInsets.all(18), children: [
    const SizedBox(height: 16),
    const Center(child: CircleAvatar(radius: 45, backgroundColor: crimson, child: Icon(Icons.person, size: 48, color: Colors.white))),
    const SizedBox(height: 15),
    Center(child: Text(username, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold))),
    Center(child: Text(demo ? 'Demo preview' : 'Connected employee', style: const TextStyle(color: Colors.white54))),
    const SizedBox(height: 12),
    Card(child:ListTile(leading:const Icon(Icons.shield),title:const Text('Role'),subtitle:Text(role))),
    Card(child:ListTile(leading:const Icon(Icons.business),title:const Text('Company'),
      subtitle:Text((user['company_name']??'RCONSOFT').toString()))),
    const SizedBox(height: 20),
    Card(child: ListTile(leading: const Icon(Icons.dns), title: const Text('API Server'), subtitle: Text(demo ? 'Demo mode / no live sync' : api.base))),
    Card(child: ListTile(leading: const Icon(Icons.info_outline), title: const Text('App version'), subtitle: const Text('1.0.0 • Android'))),
    const SizedBox(height: 20),
    FilledButton.icon(onPressed: () async {
      if (!demo) { try { await api.request('/logout', method: 'POST'); } catch (_) {} }
      setState(() {signedIn=false;api.token='';role='';user={};stats={};leads=[];hrmsTasks=[];employees=[];tab=0;demo=false;});
    }, icon: const Icon(Icons.logout), label: const Text('Sign out')),
  ]);

  Widget leadCard(Map<String, dynamic> lead) => Card(child: ListTile(
    leading: CircleAvatar(backgroundColor: crimson.withValues(alpha: 0.18), child: Text((lead['name']?.toString().isNotEmpty ?? false) ? lead['name'].toString()[0].toUpperCase() : '?', style: const TextStyle(color: crimson))),
    title: Text(lead['name']?.toString() ?? 'Unknown', maxLines: 1),
    subtitle: Text('${lead['company'] ?? ''} • ${lead['status'] ?? 'new'}', maxLines: 1),
    onTap: () => saveLead(lead),
  ));
}

class LeadsView extends StatefulWidget {
  final List<Map<String, dynamic>> leads;
  final Future<void> Function(Map<String, dynamic>?) onEdit;
  final Future<void> Function(Map<String, dynamic>) onActivity, onDelete;
  final Future<void> Function(String, String) onCall;
  const LeadsView({super.key, required this.leads, required this.onEdit, required this.onActivity, required this.onDelete, required this.onCall});
  @override
  State<LeadsView> createState() => _LeadsViewState();
}

class _LeadsViewState extends State<LeadsView> {
  String query = '';
  String filter = 'all';
  @override
  Widget build(BuildContext context) {
    final rows = widget.leads.where((l) {
      final content = '${l['name']} ${l['company']} ${l['phone']} ${l['location']}'.toLowerCase();
      return content.contains(query.toLowerCase()) && (filter == 'all' || l['status'] == filter);
    }).toList();
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 4), child: TextField(onChanged: (s) => setState(() => query = s), decoration: const InputDecoration(hintText: 'Search leads, company or phone', prefixIcon: Icon(Icons.search), filled: true, fillColor: panel, border: OutlineInputBorder()))),
      SizedBox(height: 48, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: ['all', ...statuses].map((s) => Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: ChoiceChip(label: Text(s.toUpperCase(), style: const TextStyle(fontSize: 11)), selected: filter == s, onSelected: (_) => setState(() => filter = s)))).toList())),
      Expanded(child: rows.isEmpty ? const Center(child: Text('No leads found')) : ListView.builder(padding: const EdgeInsets.fromLTRB(12, 3, 12, 85), itemCount: rows.length, itemBuilder: (ctx, i) {
        final l = rows[i];
        return Card(child: Padding(padding: const EdgeInsets.all(13), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(backgroundColor: crimson.withValues(alpha: .2), child: const Icon(Icons.person, color: crimson)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l['name']?.toString() ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text(l['company']?.toString() ?? '', style: const TextStyle(color: Colors.white60)),
            ])),
            PopupMenuButton<String>(onSelected: (action) {
              if (action == 'edit') widget.onEdit(l);
              if (action == 'activity') widget.onActivity(l);
              if (action == 'delete') widget.onDelete(l);
            }, itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit lead')),
              PopupMenuItem(value: 'activity', child: Text('Add activity')),
              PopupMenuItem(value: 'delete', child: Text('Delete lead')),
            ]),
          ]),
          const SizedBox(height: 11),
          Wrap(spacing: 9, runSpacing: 6, children: [
            Chip(label: Text(l['status']?.toString().toUpperCase() ?? 'NEW', style: const TextStyle(fontSize: 10))),
            if ((l['location']?.toString() ?? '').isNotEmpty) Chip(label: Text(l['location'].toString(), style: const TextStyle(fontSize: 10))),
          ]),
          Row(children: [
            TextButton.icon(onPressed: () => widget.onCall(l['phone']?.toString() ?? '', 'tel'), icon: const Icon(Icons.call, size: 17), label: const Text('Call')),
            TextButton.icon(onPressed: () => widget.onCall(l['phone']?.toString() ?? '', 'wa'), icon: const Icon(Icons.chat, size: 17), label: const Text('WhatsApp')),
            TextButton.icon(onPressed: () => widget.onActivity(l), icon: const Icon(Icons.note_add, size: 17), label: const Text('Notes')),
          ]),
        ])));
      })),
    ]);
  }
}
