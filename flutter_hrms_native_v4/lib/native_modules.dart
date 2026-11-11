part of 'main.dart';

// Flutter-native HRMS pages. No embedded website, HTML or WebView is used here.

void _toast(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> _confirmAction(BuildContext context, String title, String body) async =>
  (await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
    title:Text(title),content:Text(body),actions:[
      TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),
      FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Confirm')),
    ])))??false;

void _openNative(BuildContext context, Widget child, String title) {
  Navigator.push(context,MaterialPageRoute(builder:(_)=>Scaffold(
    appBar:AppBar(title:Text(title)),body:child)));
}

class _EmployeesPage extends StatefulWidget {
  final Api api;
  final void Function(String) onMessage;
  const _EmployeesPage({required this.api,required this.onMessage});
  @override State<_EmployeesPage> createState()=>_EmployeesPageState();
}
class _EmployeesPageState extends State<_EmployeesPage> {
  final listKey=GlobalKey<_ListPageState>();
  Future<void> _credentials(Map<String,dynamic> res) async {
    final data=_map(res['temporary_credentials']);
    if(data.isEmpty)return;
    final pass=_str(data['password'],'');
    await showDialog<void>(context:context,barrierDismissible:false,builder:(ctx)=>AlertDialog(
      title:const Text('Temporary employee login'),
      content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('Share these credentials securely. The temporary password is shown only once.'),
        const SizedBox(height:14),SelectableText('Email: ${_str(data['email'])}'),
        const SizedBox(height:8),SelectableText('Password: $pass'),
      ]),actions:[FilledButton(onPressed:()=>Navigator.pop(ctx),child:const Text('I have saved it'))],
    ));
  }
  Future<void> _action(Map<String,dynamic> item, String action,Future<void> Function() reload)async {
    final desc=action=='delete'?'Delete this employee and disable their login?':
      action=='reset-password'?'Reset this employee login password?':'Create a login for this employee?';
    if(!await _confirmAction(context,action=='delete'?'Delete employee':'Confirm login action',desc))return;
    try{
      final path='/employees/${item['id']}';
      final res=await widget.api.call(action=='delete'?path:'$path/$action',
        method:action=='delete'?'DELETE':'POST');
      if(!mounted)return;
      await reload();
      widget.onMessage(_str(res['message'],'Action completed'));
      await _credentials(res);
    }catch(e){widget.onMessage(_humanError(e));}
  }
  Future<void> _edit(Map<String,dynamic>? item) async {
    final values=<String,TextEditingController>{};
    for(final key in ['employee_code','first_name','last_name','email','phone','department',
      'designation','joining_date','date_of_birth','salary','manager_name']){
      var v=_str(item?[key],'');
      if(['joining_date','date_of_birth'].contains(key)&&v.length>=10)v=v.substring(0,10);
      values[key]=TextEditingController(text:v);
    }
    String type=_str(item?['employment_type'],'Full-time');
    String status=_str(item?['status'],'Active');
    if(!['Full-time','Part-time','Contract','Intern'].contains(type))type='Full-time';
    if(!['Active','On Leave','Inactive'].contains(status))status='Active';
    await showModalBottomSheet<void>(context:context,isScrollControlled:true,backgroundColor:_card,
      builder:(ctx)=>StatefulBuilder(builder:(ctx,change)=>Padding(
        padding:EdgeInsets.fromLTRB(18,16,18,MediaQuery.viewInsetsOf(ctx).bottom+24),
        child:FractionallySizedBox(heightFactor:0.86,child:ListView(children:[
          Text(item==null?'Add Employee':'Edit Employee',style:const TextStyle(fontSize:21,fontWeight:FontWeight.w800)),
          const SizedBox(height:8),
          const Text('Details match the Laravel HRMS employee form.',style:TextStyle(color:_muted,fontSize:12)),
          const SizedBox(height:14),
          for(final pair in const [
            ['employee_code','Employee code *'],['first_name','First name *'],['last_name','Last name'],
            ['email','Work email *'],['phone','Phone'],['department','Department'],
            ['designation','Designation'],['joining_date','Joining date (YYYY-MM-DD)'],
            ['date_of_birth','Date of birth (YYYY-MM-DD) *'],['salary','Salary (₹)'],['manager_name','Manager name']])...[
            TextField(controller:values[pair[0]],keyboardType:pair[0]=='salary'?TextInputType.number:
              pair[0]=='email'?TextInputType.emailAddress:TextInputType.text,
              decoration:InputDecoration(labelText:pair[1])),const SizedBox(height:9),
          ],
          DropdownButtonFormField<String>(value:type,decoration:const InputDecoration(labelText:'Employment type'),
            items:['Full-time','Part-time','Contract','Intern'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),
            onChanged:(v)=>change(()=>type=v??type)),const SizedBox(height:9),
          DropdownButtonFormField<String>(value:status,decoration:const InputDecoration(labelText:'Status'),
            items:['Active','On Leave','Inactive'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),
            onChanged:(v)=>change(()=>status=v??status)),const SizedBox(height:16),
          FilledButton.icon(icon:const Icon(Icons.save),label:Text(item==null?'Create Employee':'Save Changes'),onPressed:()async {
            final data=<String,dynamic>{};
            for(final key in values.keys){
              final t=values[key]!.text.trim();
              data[key]=t.isEmpty?null:t;
            }
            data['employment_type']=type;data['status']=status;
            if(data['salary']!=null)data['salary']=double.tryParse(data['salary'].toString());
            try{
              final res=await widget.api.call(item==null?'/employees':'/employees/${item['id']}',
                method:item==null?'POST':'PATCH',data:data);
              if(ctx.mounted)Navigator.pop(ctx);
              await listKey.currentState?.load();
              if(!mounted)return;
              widget.onMessage(_str(res['message'],'Employee saved'));
              await _credentials(res);
            }catch(e){widget.onMessage(_humanError(e));}
          }),
        ])),
      )));
    for(final v in values.values){v.dispose();}
  }
  @override Widget build(BuildContext context)=>Stack(children:[
    _ListPage(key:listKey,api:widget.api,title:'Employees',endpoint:'/employees',icon:Icons.badge,
      itemBuilder:(item,reload)=>Padding(padding:const EdgeInsets.only(bottom:2),child:_Panel(child:Column(children:[
        ListTile(contentPadding:EdgeInsets.zero,
          leading:const CircleAvatar(backgroundColor:Color(0x334BD5A2),child:Icon(Icons.person,color:_green)),
          title:Text('${_str(item['first_name'],'')} ${_str(item['last_name'],'')}',style:const TextStyle(fontWeight:FontWeight.w800)),
          subtitle:Text('${_str(item['employee_code'])} • ${_str(item['department'])}\n${_str(item['designation'])}'),
          isThreeLine:true,trailing:_Chip(label:_str(item['status'])),
          onTap:()=>_edit(item)),
        Wrap(spacing:5,runSpacing:3,children:[
          TextButton.icon(onPressed:()=>_edit(item),icon:const Icon(Icons.edit,size:17),label:const Text('Edit')),
          PopupMenuButton<String>(tooltip:'Login actions',onSelected:(v)=>_action(item,v,reload),
            itemBuilder:(_)=>const [PopupMenuItem(value:'create-login',child:Text('Create login')),
              PopupMenuItem(value:'reset-password',child:Text('Reset password'))],
            icon:const Icon(Icons.lock_reset,size:21)),
          TextButton.icon(onPressed:()=>_action(item,'delete',reload),
            icon:const Icon(Icons.delete_outline,size:17),label:const Text('Delete')),
        ]),
      ])) )),
    Positioned(bottom:18,right:18,child:FloatingActionButton.extended(
      heroTag:'employee_add',backgroundColor:_red,foregroundColor:Colors.white,
      onPressed:()=>_edit(null),icon:const Icon(Icons.add),label:const Text('Add Employee'))),
  ]);
}

class _BirthdaysPage extends StatelessWidget {
  final Api api;
  const _BirthdaysPage({required this.api});
  @override Widget build(BuildContext context)=>_ListPage(api:api,title:'Employee Birthdays',
    endpoint:'/birthdays',icon:Icons.cake_outlined,itemBuilder:(x,reload)=>_Panel(child:Row(children:[
      CircleAvatar(backgroundColor:const Color(0x33E9474B),child:Icon(x['days_left']==0?Icons.cake:Icons.event,color:_red)),
      const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(_str(x['name']),style:const TextStyle(fontWeight:FontWeight.w800)),
        Text('Next: ${_str(x['next_birthday'])}',style:const TextStyle(color:_muted,fontSize:12)),
        Text('Turning ${_str(x['turning_age'])}',style:const TextStyle(color:_muted,fontSize:11)),
      ])),
      _Chip(label:x['days_left']==0?'TODAY':'${_str(x['days_left'])}d'),
    ])));
}

class _ReportsPage extends StatefulWidget {
  final Api api;
  final void Function(String) onMessage;
  const _ReportsPage({required this.api,required this.onMessage});
  @override State<_ReportsPage> createState()=>_ReportsPageState();
}
class _ReportsPageState extends State<_ReportsPage> {
  Map<String,dynamic> data={};bool busy=true;String? error;
  late DateTime from=DateTime(DateTime.now().year,DateTime.now().month,1);
  late DateTime to=DateTime.now();
  @override void initState(){super.initState();load();}
  String day(DateTime dt)=>'${dt.year.toString().padLeft(4,'0')}-${dt.month.toString().padLeft(2,'0')}-${dt.day.toString().padLeft(2,'0')}';
  Future<void> load()async{
    setState((){busy=true;error=null;});
    try{final r=await widget.api.call('/reports?from=${day(from)}&to=${day(to)}');
      if(mounted)setState(()=>data=r);
    }catch(e){if(mounted)setState(()=>error=_humanError(e));}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> choose(bool start)async{
    final dt=await showDatePicker(context:context,initialDate:start?from:to,
      firstDate:DateTime(2020),lastDate:DateTime.now().add(const Duration(days:365)));
    if(dt!=null){setState((){if(start)from=dt;else to=dt;});await load();}
  }
  Future<void> export()async{
    final rows=_items(data['attendance_rows']);
    final csv=StringBuffer('Work date,Employee code,Employee name,Check in,Check out,Status\r\n');
    String cell(Object? v)=>'"${_str(v,'').replaceAll('"','""')}"';
    for(final r in rows){csv.writeln(['work_date','employee_code','employee_name','check_in','check_out','status']
      .map((k)=>cell(r[k])).join(','));}
    try{
      final dir=await getTemporaryDirectory();
      final file=File('${dir.path}/rconsoft_attendance_${day(from)}_${day(to)}.csv');
      await file.writeAsString(csv.toString(),flush:true);
      await SharePlus.instance.share(ShareParams(files:[XFile(file.path)],text:'RCONSOFT attendance report'));
    }catch(e){widget.onMessage(_humanError(e));}
  }
  @override Widget build(BuildContext context){
    final stats=_map(data['summary']);final rows=_items(data['attendance_rows']);
    return RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(18),children:[
      const _Title('Reports & Analytics',subtitle:'Live data from your tenant database'),
      const SizedBox(height:16),
      _Panel(child:Row(children:[
        Expanded(child:OutlinedButton.icon(onPressed:()=>choose(true),icon:const Icon(Icons.date_range),label:Text('From ${day(from)}'))),
        const SizedBox(width:8),Expanded(child:OutlinedButton.icon(onPressed:()=>choose(false),icon:const Icon(Icons.event),label:Text('To ${day(to)}'))),
      ])),const SizedBox(height:15),
      if(busy)const LinearProgressIndicator(),
      if(error!=null)_ErrorPanel(error:error!,retry:load),
      if(!busy&&error==null)...[
        for(final stat in stats.entries)Padding(padding:const EdgeInsets.only(bottom:8),child:_Panel(
          child:Row(children:[const Icon(Icons.analytics_outlined,color:_red),const SizedBox(width:12),
            Expanded(child:Text(stat.key.replaceAll('_',' ').toUpperCase())),
            Text(_str(stat.value,'0'),style:const TextStyle(fontSize:20,fontWeight:FontWeight.w800))]))),
        const SizedBox(height:12),
        FilledButton.icon(onPressed:export,icon:const Icon(Icons.ios_share),label:const Text('Export / Share Attendance CSV')),
        const SizedBox(height:20),
        Text('Attendance records (${rows.length})',style:const TextStyle(fontSize:17,fontWeight:FontWeight.w800)),
        const SizedBox(height:12),
        if(rows.isEmpty)const _Panel(child:Text('No records in this period.')),
        ...rows.map((r)=>Padding(padding:const EdgeInsets.only(bottom:8),child:_Panel(child:Column(
          crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(_str(r['employee_name']),style:const TextStyle(fontWeight:FontWeight.w800)),
          Text('${_str(r['work_date'])} • ${_str(r['employee_code'])}',style:const TextStyle(color:_muted,fontSize:12)),
          Text('In ${_str(r['check_in'])} | Out ${_str(r['check_out'])}',style:const TextStyle(color:_muted,fontSize:11)),
        ])))),
      ]
    ]));
  }
}

class _PerformancePage extends StatefulWidget {
  final Api api;
  const _PerformancePage({required this.api});
  @override State<_PerformancePage> createState()=>_PerformancePageState();
}
class _PerformancePageState extends State<_PerformancePage> {
  bool busy=true;String? error;Map<String,dynamic> data={};
  @override void initState(){super.initState();load();}
  Future<void> load()async{
    setState((){busy=true;error=null;});
    try{final r=await widget.api.call('/performance');if(mounted)setState(()=>data=r);}
    catch(e){if(mounted)setState(()=>error=_humanError(e));}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context){
    final stats=_map(data['summary']);final tasks=_items(data['tasks']);
    return RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(18),children:[
      const _Title('My Performance',subtitle:'Tasks, completion and attendance'),const SizedBox(height:15),
      if(busy)const LinearProgressIndicator(),if(error!=null)_ErrorPanel(error:error!,retry:load),
      for(final item in stats.entries)Padding(padding:const EdgeInsets.only(bottom:9),child:_Panel(child:Row(children:[
        const Icon(Icons.auto_graph,color:_green),const SizedBox(width:12),
        Expanded(child:Text(item.key.replaceAll('_',' ').toUpperCase())),
        Text(_str(item.value),style:const TextStyle(fontSize:21,fontWeight:FontWeight.w800)),
      ]))),
      const SizedBox(height:18),const Text('Assigned work',style:TextStyle(fontSize:17,fontWeight:FontWeight.w800)),
      const SizedBox(height:10),...tasks.map((t)=>Padding(padding:const EdgeInsets.only(bottom:8),
        child:_Panel(child:ListTile(title:Text(_str(t['title'])),subtitle:Text(_str(t['due_date'])),
          trailing:_Chip(label:_str(t['status'])))))),
    ]));
  }
}

class _ProfileSettings extends StatefulWidget {
  final Api api;
  final void Function(String) onMessage;
  const _ProfileSettings({required this.api,required this.onMessage});
  @override State<_ProfileSettings> createState()=>_ProfileSettingsState();
}
class _ProfileSettingsState extends State<_ProfileSettings> {
  final name=TextEditingController(),email=TextEditingController(),phone=TextEditingController();
  bool busy=true;
  @override void initState(){super.initState();load();}
  @override void dispose(){name.dispose();email.dispose();phone.dispose();super.dispose();}
  Future<void> load()async{
    try{final data=_map((await widget.api.call('/profile'))['data']);
      name.text=_str(data['name'],'');email.text=_str(data['email'],'');phone.text=_str(data['phone'],'');
    }catch(e){widget.onMessage(_humanError(e));}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(18),children:[
    const _Title('My Profile'),const SizedBox(height:18),if(busy)const LinearProgressIndicator(),
    if(!busy)_Panel(child:Column(children:[
      TextField(controller:name,decoration:const InputDecoration(labelText:'Full name *')),
      const SizedBox(height:10),TextField(controller:email,keyboardType:TextInputType.emailAddress,
        decoration:const InputDecoration(labelText:'Email ID *')),
      const SizedBox(height:10),TextField(controller:phone,decoration:const InputDecoration(labelText:'Phone')),
      const SizedBox(height:18),FilledButton.icon(onPressed:()async{
        try{final res=await widget.api.call('/profile',method:'PATCH',data:{'name':name.text.trim(),
          'email':email.text.trim(),'phone':phone.text.trim()});
          widget.onMessage(_str(res['message'],'Profile updated'));}
        catch(e){widget.onMessage(_humanError(e));}
      },icon:const Icon(Icons.save),label:const Text('Save Profile')),
    ])),const SizedBox(height:18),OutlinedButton.icon(onPressed:()=>_openNative(context,
      _PasswordPage(api:widget.api,onMessage:widget.onMessage),'Change password'),
      icon:const Icon(Icons.lock_outline),label:const Text('Change Password')),
  ]);
}

class _PasswordPage extends StatefulWidget {
  final Api api;
  final void Function(String) onMessage;
  final VoidCallback? onChanged;
  const _PasswordPage({required this.api,required this.onMessage,this.onChanged});
  @override State<_PasswordPage> createState()=>_PasswordPageState();
}
class _PasswordPageState extends State<_PasswordPage> {
  final current=TextEditingController(),password=TextEditingController(),confirm=TextEditingController();
  bool reveal=false;
  @override void dispose(){current.dispose();password.dispose();confirm.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(18),children:[
    const _Title('Change Password',subtitle:'Other mobile sessions will be revoked'),
    const SizedBox(height:16),
    TextField(controller:current,obscureText:!reveal,decoration:const InputDecoration(labelText:'Current password')),
    const SizedBox(height:10),TextField(controller:password,obscureText:!reveal,decoration:const InputDecoration(labelText:'New password (8+ characters)')),
    const SizedBox(height:10),TextField(controller:confirm,obscureText:!reveal,decoration:const InputDecoration(labelText:'Confirm new password')),
    SwitchListTile(value:reveal,onChanged:(v)=>setState(()=>reveal=v),title:const Text('Show passwords')),
    const SizedBox(height:14),FilledButton.icon(icon:const Icon(Icons.lock_reset),label:const Text('Update Password'),onPressed:()async{
      if(password.text!=confirm.text){widget.onMessage('Passwords do not match');return;}
      try{
        final res=await widget.api.call('/password/change',method:'POST',data:{
          'current_password':current.text,'password':password.text,
          'password_confirmation':confirm.text});
        current.clear();password.clear();confirm.clear();
        widget.onMessage(_str(res['message'],'Password changed'));
        widget.onChanged?.call();
        if(widget.onChanged==null&&context.mounted)Navigator.pop(context);
      }catch(e){widget.onMessage(_humanError(e));}
    }),
  ]);
}

class _TenantsPage extends StatefulWidget {
  final Api api;
  final void Function(String) onMessage;
  const _TenantsPage({required this.api,required this.onMessage});
  @override State<_TenantsPage> createState()=>_TenantsPageState();
}
class _TenantsPageState extends State<_TenantsPage> {
  final listKey=GlobalKey<_ListPageState>();
  void openTenant(Map<String,dynamic> item){
    _openNative(context,_TenantDetail(api:widget.api,id:item['id'] as int,onMessage:widget.onMessage),_str(item['name']));
  }
  @override Widget build(BuildContext context)=>Stack(children:[
    _ListPage(key:listKey,api:widget.api,title:'All Companies',endpoint:'/super-admin/tenants',
      icon:Icons.apartment,itemBuilder:(t,reload)=>_Panel(child:ListTile(
        leading:const CircleAvatar(backgroundColor:Color(0x33E9474B),child:Icon(Icons.apartment,color:_red)),
        title:Text(_str(t['name']),style:const TextStyle(fontWeight:FontWeight.w800)),
        subtitle:Text('${_str(t['slug'])} • ${t['database_ready_at']==null?'DB not initialized':'DB ready'}'),
        trailing:const Icon(Icons.chevron_right),onTap:()=>openTenant(t)))),
    Positioned(bottom:18,right:18,child:FloatingActionButton.extended(heroTag:'tenant_add',
      backgroundColor:_red,foregroundColor:Colors.white,
      onPressed:()=>_openNative(context,_CreateTenant(api:widget.api,onMessage:widget.onMessage),
        'Create Tenant'),icon:const Icon(Icons.add_business),label:const Text('New Tenant'))),
  ]);
}

class _CreateTenant extends StatefulWidget {
  final Api api;final void Function(String) onMessage;
  const _CreateTenant({required this.api,required this.onMessage});
  @override State<_CreateTenant> createState()=>_CreateTenantState();
}
class _CreateTenantState extends State<_CreateTenant> {
  final values=<String,TextEditingController>{};
  bool busy=false,showSecrets=false;
  @override void initState(){super.initState();for(final key in [
    'name','slug','email','phone','db_host','db_port','db_database','db_username','db_password',
    'admin_name','admin_email','admin_password','admin_password_confirmation']){
      values[key]=TextEditingController(text:key=='db_host'?'localhost':key=='db_port'?'3306':'');
    }}
  @override void dispose(){for(final v in values.values){v.dispose();}super.dispose();}
  @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(18),children:[
    const _Title('New company tenant',subtitle:'Database must first be created in cPanel / MySQL'),
    const SizedBox(height:16),
    for(final pair in const [
      ['name','Company name *'],['slug','Slug (lowercase, hyphen) *'],['email','Company email'],
      ['phone','Phone'],['db_host','DB Host *'],['db_port','DB Port *'],
      ['db_database','Independent database name *'],['db_username','Database user *'],
      ['db_password','Database password *'],['admin_name','Admin name *'],['admin_email','Admin email *'],
      ['admin_password','Admin password (12+ chars) *'],['admin_password_confirmation','Confirm admin password *']])...[
      TextField(controller:values[pair[0]],obscureText:pair[0].contains('password')&&!showSecrets,
        decoration:InputDecoration(labelText:pair[1])),const SizedBox(height:10),
    ],
    SwitchListTile(title:const Text('Show password fields'),value:showSecrets,onChanged:(v)=>setState(()=>showSecrets=v)),
    const SizedBox(height:14),FilledButton.icon(onPressed:busy?null:()async{
      setState(()=>busy=true);
      try{
        final data=<String,dynamic>{};for(final key in values.keys){
          final v=values[key]!.text.trim();data[key]=v.isEmpty?null:v;
        }
        final res=await widget.api.call('/super-admin/tenants',method:'POST',data:data);
        widget.onMessage(_str(res['message'],'Tenant created'));
        if(context.mounted)Navigator.pop(context);
      }catch(e){widget.onMessage(_humanError(e));}
      finally{if(mounted)setState(()=>busy=false);}
    },icon:const Icon(Icons.save),label:const Text('Create Tenant & Admin')),
    const SizedBox(height:12),const Text('This does not create a cPanel MySQL database. Only an existing isolated database can be initialized.',
      style:TextStyle(color:_muted,fontSize:12)),
  ]);
}

class _TenantDetail extends StatefulWidget {
  final Api api;final int id;final void Function(String) onMessage;
  const _TenantDetail({required this.api,required this.id,required this.onMessage});
  @override State<_TenantDetail> createState()=>_TenantDetailState();
}
class _TenantDetailState extends State<_TenantDetail> {
  Map<String,dynamic> tenant={};bool loading=true;
  final host=TextEditingController(),port=TextEditingController(),database=TextEditingController(),username=TextEditingController(),password=TextEditingController();
  @override void initState(){super.initState();load();}
  @override void dispose(){host.dispose();port.dispose();database.dispose();username.dispose();password.dispose();super.dispose();}
  Future<void> load()async{
    setState(()=>loading=true);
    try{
      tenant=_map((await widget.api.call('/super-admin/tenants/${widget.id}'))['data']);
      host.text=_str(tenant['db_host'],'localhost');port.text=_str(tenant['db_port'],'3306');
      database.text=_str(tenant['db_database'],'');username.text=_str(tenant['db_username'],'');
    }catch(e){widget.onMessage(_humanError(e));}
    finally{if(mounted)setState(()=>loading=false);}
  }
  Future<void> doAction(String action,Map<String,dynamic> data,String title)async{
    if(!await _confirmAction(context,title,'Confirm this action for ${_str(tenant['name'])}?'))return;
    try{
      final res=await widget.api.call('/super-admin/tenants/${widget.id}/$action',
        method:action=='active'||action=='connection'?'PATCH':'POST',data:data);
      widget.onMessage(_str(res['message'],'Updated'));
      await load();
    }catch(e){widget.onMessage(_humanError(e));}
  }
  @override Widget build(BuildContext context)=>RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(18),children:[
    const _Title('Company Settings'),const SizedBox(height:15),if(loading)const LinearProgressIndicator(),
    if(!loading)...[
      _Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(_str(tenant['name']),style:const TextStyle(fontSize:21,fontWeight:FontWeight.w800)),
        Text('Slug: ${_str(tenant['slug'])}',style:const TextStyle(color:_muted)),
        const SizedBox(height:7),Text('DB: ${_str(tenant['db_database'])}',style:const TextStyle(color:_muted)),
        Text('Ready: ${tenant['database_ready_at']==null?'Not initialized':'Yes'}',style:const TextStyle(color:_muted)),
        Text('Active: ${tenant['is_active']==true?'Yes':'No'}',style:const TextStyle(color:_muted)),
        const SizedBox(height:12),FilledButton.icon(onPressed:()=>doAction('active',{'is_active':tenant['is_active']!=true},
          tenant['is_active']==true?'Suspend tenant':'Activate tenant'),
          icon:const Icon(Icons.power_settings_new),label:Text(tenant['is_active']==true?'Suspend':'Activate')),
      ])),const SizedBox(height:16),
      const Text('Database connection',style:TextStyle(fontSize:18,fontWeight:FontWeight.w800)),
      const SizedBox(height:10),
      for(final pair in [
        ['Host',host],['Port',port],['Database',database],['Username',username],['New password (optional)',password]])...[
        TextField(controller:pair[1] as TextEditingController,obscureText:pair[0]=='New password (optional)',
          decoration:InputDecoration(labelText:pair[0] as String)),const SizedBox(height:9),
      ],
      FilledButton.icon(onPressed:()=>doAction('connection',{
        'db_host':host.text.trim(),'db_port':int.tryParse(port.text.trim())??3306,
        'db_database':database.text.trim(),'db_username':username.text.trim(),
        'db_password':password.text.trim().isEmpty?null:password.text.trim()},'Save DB connection'),
        icon:const Icon(Icons.save_outlined),label:const Text('Save Database Settings')),
      const SizedBox(height:8),OutlinedButton.icon(onPressed:()=>doAction('initialize',{},'Initialize tenant database'),
        icon:const Icon(Icons.storage_outlined),label:const Text('Initialize Database')),
      const SizedBox(height:18),const Text('Company logins',style:TextStyle(fontSize:18,fontWeight:FontWeight.w800)),
      for(final u in _items(tenant['users']))_Panel(child:ListTile(
        leading:const Icon(Icons.person_outline,color:_red),title:Text(_str(u['name'])),
        subtitle:Text('${_str(u['email'])} • ${_str(u['role'])}'))),
      const SizedBox(height:12),const Text('Subscription history',style:TextStyle(fontSize:18,fontWeight:FontWeight.w800)),
      for(final r in _items(tenant['requests']))_Panel(child:ListTile(
        title:Text('${_str(r['plan_months'])} months'),subtitle:Text(_str(r['status'])))),
    ],
  ]));
}