import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'api.dart';

const bg = Color(0xFF080C17);
const panel = Color(0xFF111A2B);
const panel2 = Color(0xFF19263A);
const red = Color(0xFFFF3C57);
const cyan = Color(0xFF52D9E7);
const muted = Color(0xFF9CAFC4);

void main() { WidgetsFlutterBinding.ensureInitialized(); runApp(const MyGymApp()); }

class MyGymApp extends StatelessWidget {
  const MyGymApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'MyGym Workspace', debugShowCheckedModeBanner: false,
    theme: ThemeData(brightness: Brightness.dark, useMaterial3: true,
      scaffoldBackgroundColor: bg, colorScheme: const ColorScheme.dark(primary: red, secondary: cyan, surface: panel),
      appBarTheme: const AppBarTheme(backgroundColor: bg, foregroundColor: Colors.white),
      inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: panel2,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15)),
      cardTheme: CardThemeData(color: panel, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
    ), home: const Gate());
}

class Gate extends StatefulWidget { const Gate({super.key}); @override State<Gate> createState() => _GateState(); }
class _GateState extends State<Gate> {
  final api = GymApi(); bool waiting=true, logged=false;
  @override void initState(){super.initState();_restore();}
  Future<void> _restore() async { final ok=await api.restore(); if(mounted)setState((){logged=ok;waiting=false;}); }
  void _onLogin(){if(mounted)setState(()=>logged=true);}
  Future<void> _logout() async {await api.logout();if(mounted)setState(()=>logged=false);}
  @override Widget build(BuildContext context) => waiting
    ? const Scaffold(body: Center(child:CircularProgressIndicator(color:red)))
    : logged ? Workspace(api:api,onLogout:_logout) : SignIn(api:api,onLogin:_onLogin);
}

class SignIn extends StatefulWidget { final GymApi api; final VoidCallback onLogin;
  const SignIn({super.key, required this.api, required this.onLogin});
  @override State<SignIn> createState()=>_SignInState(); }
class _SignInState extends State<SignIn>{
  final user=TextEditingController(), password=TextEditingController(), code=TextEditingController();
  bool owner=false, loading=false, visible=false;String? error;
  @override void dispose(){user.dispose();password.dispose();code.dispose();super.dispose();}
  Future<void> submit() async{
    setState(() {loading=true;error=null;});
    try{await widget.api.login(type:owner?'owner':'gym',code:code.text,username:user.text,password:password.text);
      widget.onLogin();
    }catch(e){if(mounted)setState(()=>error=e.toString());}
    finally{if(mounted)setState(()=>loading=false);}
  }
  @override Widget build(BuildContext context)=>Scaffold(body:SafeArea(child:
    Center(child:SingleChildScrollView(padding:const EdgeInsets.all(22),child:ConstrainedBox(
      constraints:const BoxConstraints(maxWidth:450),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Container(alignment:Alignment.center,margin:const EdgeInsets.only(bottom:18),child:
          const CircleAvatar(radius:37,backgroundColor:panel2,child:Icon(Icons.fitness_center,color:red,size:38))),
        const Text('MyGym Workspace',textAlign:TextAlign.center,style:TextStyle(fontSize:29,fontWeight:FontWeight.w900)),
        const SizedBox(height:7),const Text('Powered by RconSoft • Secure Gym Cloud',textAlign:TextAlign.center,style:TextStyle(color:muted)),
        const SizedBox(height:30),Container(padding:const EdgeInsets.all(5),decoration:BoxDecoration(color:panel,borderRadius:BorderRadius.circular(13)),
        child:Row(children:[Expanded(child:_mode('Gym Workspace',!owner,()=>setState(()=>owner=false))),
          Expanded(child:_mode('RconSoft Owner',owner,()=>setState(()=>owner=true)))])),
        const SizedBox(height:22),if(!owner)...[
          const FieldLabel('GYM CODE'),TextField(controller:code,textCapitalization:TextCapitalization.characters,
            decoration:const InputDecoration(hintText:'BESTRONG / GKFITNESS',prefixIcon:Icon(Icons.business))),const SizedBox(height:15)],
        const FieldLabel('USERNAME'),TextField(controller:user,decoration:const InputDecoration(hintText:'Enter username',prefixIcon:Icon(Icons.person_outline))),
        const SizedBox(height:15),const FieldLabel('PASSWORD'),TextField(controller:password,obscureText:!visible,
          decoration:InputDecoration(hintText:'Password',prefixIcon:const Icon(Icons.lock_outline),
            suffixIcon:IconButton(onPressed:()=>setState(()=>visible=!visible),icon:Icon(visible?Icons.visibility_off:Icons.visibility)))),
        if(error!=null)Padding(padding:const EdgeInsets.only(top:15),child:Text(error!,style:const TextStyle(color:red))),
        const SizedBox(height:24),FilledButton(onPressed:loading?null:submit,style:FilledButton.styleFrom(minimumSize:const Size.fromHeight(54)),
          child:loading?const SizedBox(height:20,width:20,child:CircularProgressIndicator(strokeWidth:2)):
          const Text('SECURE SIGN IN',style:TextStyle(fontWeight:FontWeight.bold))),
        const SizedBox(height:20),const Text('Each gym has its own private database. QR and payments belong only to that gym.',
          textAlign:TextAlign.center,style:TextStyle(color:muted,fontSize:12))
      ]))))));
  Widget _mode(String text,bool active,VoidCallback tap)=>InkWell(onTap:tap,borderRadius:BorderRadius.circular(10),
    child:Container(padding:const EdgeInsets.symmetric(vertical:13),decoration:BoxDecoration(
      color:active?red:Colors.transparent,borderRadius:BorderRadius.circular(10)),
      child:Text(text,textAlign:TextAlign.center,style:TextStyle(fontWeight:FontWeight.bold,color:active?Colors.white:muted))));
}

class Workspace extends StatefulWidget {
 final GymApi api; final Future<void> Function() onLogout;
 const Workspace({super.key,required this.api,required this.onLogout});
 @override State<Workspace> createState()=>_WorkspaceState();
}
class _WorkspaceState extends State<Workspace> {
 int tab=0;
 @override Widget build(BuildContext context){
  final owner=widget.api.owner;
  final items=owner? <_Tab>[_Tab('Gyms',Icons.apartment),_Tab('Account',Icons.person_outline)] :
    <_Tab>[_Tab('Dashboard',Icons.space_dashboard_rounded),_Tab('Members',Icons.groups_rounded),
      _Tab('Payments',Icons.payments_outlined),if(widget.api.admin)_Tab('Attendance',Icons.how_to_reg_outlined),
      _Tab('UPI Settings',Icons.qr_code_2_rounded)];
  if(tab>=items.length)tab=0;
  final screens=owner?<Widget>[OwnerScreen(api:widget.api),AccountScreen(api:widget.api,onLogout:widget.onLogout)] :
    <Widget>[DashboardScreen(api:widget.api),MembersScreen(api:widget.api),PaymentsScreen(api:widget.api),
      if(widget.api.admin)AttendanceScreen(api:widget.api),UpiScreen(api:widget.api)];
  return LayoutBuilder(builder:(context,c){
    final wide=c.maxWidth>=850;
    final content=IndexedStack(index:tab,children:screens);
    return Scaffold(appBar:AppBar(title:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('MYGYM WORKSPACE',style:TextStyle(fontSize:16,fontWeight:FontWeight.w900,letterSpacing:1)),
      Text(owner?'RCONSOFT SUPER ADMIN':widget.api.gym?['name']?.toString()??'Gym Workspace',
        style:const TextStyle(fontSize:11,color:muted))]),
      actions:[IconButton(tooltip:'Logout',onPressed:widget.onLogout,icon:const Icon(Icons.logout_rounded))]),
      body:wide?Row(children:[NavigationRail(selectedIndex:tab,onDestinationSelected:(v)=>setState(()=>tab=v),
         backgroundColor:panel,labelType:NavigationRailLabelType.all,
         destinations:items.map((i)=>NavigationRailDestination(icon:Icon(i.icon),label:Text(i.title))).toList()),
         const VerticalDivider(width:1),Expanded(child:content)]):content,
      bottomNavigationBar:wide?null:NavigationBar(height:75,backgroundColor:panel,
        selectedIndex:tab,onDestinationSelected:(v)=>setState(()=>tab=v),
        destinations:items.map((i)=>NavigationDestination(icon:Icon(i.icon,size:23),label:i.title)).toList()));
  });
 }
}
class _Tab {final String title;final IconData icon;const _Tab(this.title,this.icon);}

class AsyncScreen extends StatefulWidget {final Future<Map<String,dynamic>> Function() load;
 final Widget Function(Map<String,dynamic>) builder;
 const AsyncScreen({super.key,required this.load,required this.builder});
 @override State<AsyncScreen> createState()=>_AsyncScreenState(); }
class _AsyncScreenState extends State<AsyncScreen>{late Future<Map<String,dynamic>> pending;
 @override void initState(){super.initState();pending=widget.load();}
 void reload()=>setState(()=>pending=widget.load());
 @override Widget build(BuildContext context)=>FutureBuilder<Map<String,dynamic>>(future:pending,builder:(context,s){
   if(!s.hasData&&s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
   if(s.hasError)return ErrorPanel(s.error.toString(),retry:reload);
   return RefreshIndicator(onRefresh:()async{reload();await pending;},child:widget.builder(s.data??{}));});
}
class FieldLabel extends StatelessWidget {final String title;const FieldLabel(this.title,{super.key});
 @override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.only(bottom:8),child:Text(title,
   style:const TextStyle(color:muted,fontWeight:FontWeight.w700,fontSize:11,letterSpacing:1.2)));}
class ErrorPanel extends StatelessWidget {final String error;final VoidCallback retry;const ErrorPanel(this.error,{required this.retry,super.key});
 @override Widget build(BuildContext c)=>Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
  const Icon(Icons.error_outline,color:red,size:40),const SizedBox(height:12),
  Padding(padding:const EdgeInsets.symmetric(horizontal:20),child:Text(error,textAlign:TextAlign.center)),
  TextButton(onPressed:retry,child:const Text('Retry'))]));}
class SectionTitle extends StatelessWidget {final String title;final String? caption;
 const SectionTitle(this.title,{this.caption,super.key});
 @override Widget build(BuildContext c)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
 Text(title,style:const TextStyle(fontSize:23,fontWeight:FontWeight.w800)),
 if(caption!=null)...[const SizedBox(height:4),Text(caption!,style:const TextStyle(color:muted))]]);}
Widget tileCard({required Widget child})=>Card(margin:const EdgeInsets.only(bottom:12),child:Padding(padding:const EdgeInsets.all(16),child:child));
String money(dynamic v)=>NumberFormat.currency(locale:'en_IN',symbol:'₹',decimalDigits:0).format(num.tryParse('$v')??0);

class OwnerScreen extends StatelessWidget {final GymApi api;const OwnerScreen({super.key,required this.api});
 @override Widget build(BuildContext context)=>AsyncScreen(load:()=>api.get('/gyms'),builder:(data){
   final gyms=maps(data['gyms']);return ListView(padding:const EdgeInsets.all(16),children:[
   SectionTitle('Gym Control Center',caption:'RconSoft • Multi-database tenant registry'),const SizedBox(height:17),
   tileCard(child:Row(children:[const Icon(Icons.apartment,color:cyan,size:34),const SizedBox(width:17),
      Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('${gyms.length}',style:const TextStyle(fontSize:29,fontWeight:FontWeight.bold)),const Text('Registered gyms',style:TextStyle(color:muted))])])),
   for(final g in gyms)tileCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
     Row(children:[const Icon(Icons.fitness_center,color:red),const SizedBox(width:12),Expanded(child:Text('${g['name']}',style:const TextStyle(fontSize:17,fontWeight:FontWeight.bold))),
       Chip(label:Text('${g['status']}'),backgroundColor:g['status']=='active'?Colors.teal.shade900:panel2)]),
     const SizedBox(height:8),Text('CODE  ${g['code']}',style:const TextStyle(color:muted,letterSpacing:1)),
     const SizedBox(height:7),Text('Admins: ${g['admins_count']}    Managers: ${g['managers_count']}'),
     if(g['installed']!=true)const Text('Tenant DB installation pending',style:TextStyle(color:red)),
   ]))
 ]);});
}

class DashboardScreen extends StatelessWidget {final GymApi api;const DashboardScreen({super.key,required this.api});
 @override Widget build(BuildContext context)=>AsyncScreen(load:()=>api.get('/dashboard'),builder:(data){
   final recent=maps(data['recent_members']);
   return ListView(padding:const EdgeInsets.all(16),children:[
     SectionTitle('Overview',caption:'${api.gym?['name']??'Gym'} • Live workspace metrics'),const SizedBox(height:16),
     Wrap(spacing:10,runSpacing:10,children:[
       _metric('Total Members','${data['total_members']??0}',Icons.groups_outlined,cyan),
       _metric('Active Members','${data['active_members']??0}',Icons.check_circle_outline,Colors.greenAccent),
       _metric('Inactive','${data['inactive_members']??0}',Icons.person_off_outlined,Colors.orangeAccent),
       _metric('Check-ins Today','${data['today_checkins']??0}',Icons.how_to_reg,red),
       if(api.admin)_metric('Today Revenue',money(data['today_revenue']),Icons.currency_rupee,cyan),
       if(api.admin)_metric('Monthly Revenue',money(data['month_revenue']),Icons.trending_up,Colors.greenAccent),
     ]),const SizedBox(height:20),const SectionTitle('Recent Members'),const SizedBox(height:10),
     for(final m in recent)tileCard(child:ListTile(contentPadding:EdgeInsets.zero,leading:const CircleAvatar(backgroundColor:panel2,child:Icon(Icons.person,color:cyan)),
       title:Text('${m['name']}'),subtitle:Text('${m['member_id']} • ${m['plan']}'),trailing:Text('${m['status']}',style:const TextStyle(color:muted)))),
     if(recent.isEmpty)const Text('No members yet.',style:TextStyle(color:muted))
   ]);});
 Widget _metric(String label,String value,IconData icon,Color color)=>SizedBox(width:170,child:Container(
   padding:const EdgeInsets.all(15),decoration:BoxDecoration(color:panel,borderRadius:BorderRadius.circular(17)),
   child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(icon,color:color,size:29),const SizedBox(height:15),
     Text(value,maxLines:1,style:const TextStyle(fontSize:23,fontWeight:FontWeight.bold)),
     const SizedBox(height:4),Text(label,style:const TextStyle(color:muted,fontSize:12))])));
}

class MembersScreen extends StatefulWidget {final GymApi api;const MembersScreen({super.key,required this.api});
 @override State<MembersScreen> createState()=>_MembersScreenState();}
class _MembersScreenState extends State<MembersScreen>{
 final search=TextEditingController();String status='All';int page=1;
 @override void dispose(){search.dispose();super.dispose();}
 @override Widget build(BuildContext context)=>AsyncScreen(key:ValueKey('${search.text}|$status|$page'),
   load:()=>widget.api.get('/members',{'q':search.text,'page':'$page',if(status!='All')'status':status}),builder:(data){
   final members=maps(data['data']);return ListView(padding:const EdgeInsets.all(16),children:[
      const SectionTitle('Members',caption:'Search your gym’s private member records'),const SizedBox(height:14),
      TextField(controller:search,onSubmitted:(_)=>setState(()=>page=1),decoration:InputDecoration(
        hintText:'Name / Member ID / Phone',prefixIcon:const Icon(Icons.search),
        suffixIcon:IconButton(onPressed:()=>setState(()=>page=1),icon:const Icon(Icons.arrow_forward)))),
      const SizedBox(height:12),Wrap(spacing:7,children:['All','Active','Inactive'].map((s)=>ChoiceChip(label:Text(s),selected:status==s,
         onSelected:(_)=>setState((){status=s;page=1;}))).toList()),const SizedBox(height:12),
      Text('Found: ${data['total']??0}',style:const TextStyle(color:muted)),const SizedBox(height:9),
      for(final m in members)tileCard(child:ListTile(contentPadding:EdgeInsets.zero,
         onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>MemberDetail(api:widget.api,id:'${m['member_id']}'))),
         leading:const CircleAvatar(backgroundColor:panel2,child:Icon(Icons.person_outline,color:cyan)),
         title:Text('${m['name']}'),subtitle:Text('${m['member_id']}  •  ${m['phone']??''}\n${m['plan']}  •  ${m['status']}'),
         isThreeLine:true,trailing:const Icon(Icons.chevron_right))),
      if(members.isEmpty)const Padding(padding:EdgeInsets.all(30),child:Text('No matching members.',textAlign:TextAlign.center)),
      Row(mainAxisAlignment:MainAxisAlignment.center,children:[
        IconButton(onPressed:page>1?()=>setState(()=>page--):null,icon:const Icon(Icons.chevron_left)),
        Text('Page $page / ${data['last_page']??1}'),
        IconButton(onPressed:page<(data['last_page']??1)?()=>setState(()=>page++):null,icon:const Icon(Icons.chevron_right))])
   ]);});
}

class MemberDetail extends StatelessWidget {final GymApi api;final String id;
 const MemberDetail({super.key,required this.api,required this.id});
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(id)),
 body:AsyncScreen(load:()=>api.get('/members/${Uri.encodeComponent(id)}'),builder:(d){
   final payments=maps(d['payments']);return ListView(padding:const EdgeInsets.all(16),children:[
     SectionTitle('${d['name']}',caption:'${d['member_id']} • ${d['status']}'),const SizedBox(height:18),
     tileCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
       Text('Phone: ${d['phone']??'-'}'),Text('Plan: ${d['plan']??'-'}'),
       Text('Joining: ${d['join_date']??'-'}'),Text('Expiry: ${d['membership_end_date']??'-'}')])),
     FilledButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>PaymentForm(api:api,memberId:id))),
       icon:const Icon(Icons.add_card),label:const Text('Record Payment')),
     const SizedBox(height:19),const SectionTitle('Payment History'),const SizedBox(height:10),
     for(final p in payments)tileCard(child:ListTile(title:Text(money(p['amount'])),
       subtitle:Text('${p['pay_date']} • ${p['mode']}'),leading:const Icon(Icons.receipt_long,color:cyan)))
   ]);}));
}

class PaymentsScreen extends StatefulWidget{final GymApi api;const PaymentsScreen({super.key,required this.api});
 @override State<PaymentsScreen> createState()=>_PaymentsScreenState();}
class _PaymentsScreenState extends State<PaymentsScreen>{final memberId=TextEditingController();String? chosen;
 @override void dispose(){memberId.dispose();super.dispose();}
 @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(16),children:[
  const SectionTitle('Payments',caption:'Gym collections and member payment history'),const SizedBox(height:15),
  TextField(controller:memberId,decoration:InputDecoration(hintText:'Member ID (e.g. GKF-001)',
    prefixIcon:const Icon(Icons.badge_outlined),suffixIcon:IconButton(icon:const Icon(Icons.search),
      onPressed:()=>setState(()=>chosen=memberId.text.trim())))),const SizedBox(height:13),
  FilledButton.icon(onPressed:chosen==null||chosen!.isEmpty?null:()=>Navigator.push(context,
      MaterialPageRoute(builder:(_)=>PaymentForm(api:widget.api,memberId:chosen!))),
    icon:const Icon(Icons.add),label:const Text('Add Payment')),
  const SizedBox(height:12),if(chosen!=null && chosen!.isNotEmpty)AsyncScreen(key:ValueKey(chosen),
     load:()=>widget.api.get('/payments',{'member_id':chosen!}),builder:(data)=>Column(children:[
      for(final p in maps(data['data']))tileCard(child:ListTile(title:Text(money(p['amount'])),
        subtitle:Text('${p['member_id']}  •  ${p['pay_date']}'),trailing:Text('${p['mode']}')))
     ]))
  else const Padding(padding:EdgeInsets.all(30),child:Text('Select a member ID to view or record payments.',
       style:TextStyle(color:muted),textAlign:TextAlign.center))
 ]);
}

class PaymentForm extends StatefulWidget{final GymApi api;final String memberId;
 const PaymentForm({super.key,required this.api,required this.memberId});
 @override State<PaymentForm> createState()=>_PaymentFormState();}
class _PaymentFormState extends State<PaymentForm>{
 final cash=TextEditingController(text:'0'),online=TextEditingController(text:'0'),notes=TextEditingController();
 bool confirmed=false,saving=false;String? error;
 @override void dispose(){cash.dispose();online.dispose();notes.dispose();super.dispose();}
 Future<void> save()async{
  if(!confirmed){setState(()=>error='Verify actual receipt in bank/UPI app before saving.');return;}
  setState((){saving=true;error=null;});
  try{await widget.api.post('/payments',{'member_id':widget.memberId,'pay_date':DateFormat('yyyy-MM-dd').format(DateTime.now()),
    'cash_amount':double.tryParse(cash.text)??0,'online_amount':double.tryParse(online.text)??0,
    'notes':notes.text,'manual_confirmation':true});
    if(mounted){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Payment saved')));Navigator.pop(context);}
  }catch(e){if(mounted)setState(()=>error=e.toString());}
  finally{if(mounted)setState(()=>saving=false);}
 }
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text('Payment • ${widget.memberId}')),
 body:ListView(padding:const EdgeInsets.all(18),children:[
  const SectionTitle('Record Payment',caption:'Manual bank verification required'),const SizedBox(height:20),
  const FieldLabel('CASH AMOUNT (₹)'),TextField(controller:cash,keyboardType:const TextInputType.numberWithOptions(decimal:true),
    decoration:const InputDecoration(prefixIcon:Icon(Icons.currency_rupee))),const SizedBox(height:15),
  const FieldLabel('ONLINE AMOUNT (₹)'),TextField(controller:online,keyboardType:const TextInputType.numberWithOptions(decimal:true),
    decoration:const InputDecoration(prefixIcon:Icon(Icons.qr_code)),onChanged:(_)=>setState((){})),
  const SizedBox(height:17),if((double.tryParse(online.text)??0)>0)
    FutureBuilder<Map<String,dynamic>>(future:widget.api.get('/settings/upi'),builder:(context,s){
       final d=s.data??{};final vpa='${d['upi_vpa']??''}';final payee='${d['upi_payee']??''}';
       final total=double.tryParse(online.text)??0;
       if(vpa.isEmpty)return tileCard(child:const Text('Gym Admin must configure a UPI ID in Settings.'));
       final uri=Uri(scheme:'upi',host:'pay',queryParameters:{'pa':vpa,'pn':payee,
           'am':total.toStringAsFixed(2),'cu':'INR'}).toString();
       return tileCard(child:Column(children:[const Text('Scan to pay gym',style:TextStyle(fontWeight:FontWeight.bold)),
         const SizedBox(height:12),Container(color:Colors.white,padding:const EdgeInsets.all(10),
           child:QrImageView(data:uri,size:210,backgroundColor:Colors.white)),
         Text(money(total),style:const TextStyle(fontSize:20,fontWeight:FontWeight.w800)),
         Text(vpa,style:const TextStyle(color:muted))]));
    }),
  const FieldLabel('NOTES'),TextField(controller:notes,maxLines:2),const SizedBox(height:15),
  CheckboxListTile(value:confirmed,onChanged:(v)=>setState(()=>confirmed=v??false),
    title:const Text('Staff verified the amount was received'),
    subtitle:const Text('QR scan alone does not confirm payment.')),
  if(error!=null)Text(error!,style:const TextStyle(color:red)),const SizedBox(height:12),
  FilledButton(onPressed:saving?null:save,child:Text(saving?'Saving...':'Save Payment'))
 ]));
}

class AttendanceScreen extends StatefulWidget{final GymApi api;const AttendanceScreen({super.key,required this.api});
 @override State<AttendanceScreen> createState()=>_AttendanceScreenState();}
class _AttendanceScreenState extends State<AttendanceScreen>{
 final id=TextEditingController();String? result;bool busy=false;
 @override void dispose(){id.dispose();super.dispose();}
 Future<void> mark(String status)async{
  setState((){busy=true;result=null;});
  try{final now=DateTime.now();await widget.api.post('/attendance',{
    'member_id':id.text.trim(),'attendance_date':DateFormat('yyyy-MM-dd').format(now),
    'status':status=='checkout'?'Present':status,'action':status=='checkout'?'checkout':'checkin',
    if(status=='Present')'check_in':DateFormat('HH:mm').format(now),
    if(status=='checkout')'check_out':DateFormat('HH:mm').format(now),
  });if(mounted)setState(()=>result='Attendance saved: $status');}
  catch(e){if(mounted)setState(()=>result=e.toString());}
  finally{if(mounted)setState(()=>busy=false);}
 }
 @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(16),children:[
  const SectionTitle('Attendance',caption:'Mark today’s gym member attendance'),const SizedBox(height:15),
  TextField(controller:id,decoration:const InputDecoration(labelText:'Member ID',prefixIcon:Icon(Icons.badge_outlined))),
  const SizedBox(height:15),FilledButton.icon(onPressed:busy?null:()=>mark('Present'),icon:const Icon(Icons.login),label:const Text('Check In / Present')),
  const SizedBox(height:9),OutlinedButton.icon(onPressed:busy?null:()=>mark('checkout'),icon:const Icon(Icons.logout),label:const Text('Check Out')) ,
  const SizedBox(height:9),OutlinedButton(onPressed:busy?null:()=>mark('Absent'),child:const Text('Mark Absent')),
  if(result!=null)Padding(padding:const EdgeInsets.all(14),child:Text(result!,style:const TextStyle(color:cyan))),
  const SizedBox(height:20),AsyncScreen(load:()=>widget.api.get('/attendance'),builder:(d)=>Column(
    crossAxisAlignment:CrossAxisAlignment.start,children:[const SectionTitle('Today’s Log'),const SizedBox(height:10),
    for(final a in maps(d['data']))tileCard(child:ListTile(title:Text('${a['member_id']}'),
       subtitle:Text('${a['check_in']??''}'),trailing:Text('${a['status']}')))]))
 ]);
}

class UpiScreen extends StatefulWidget{final GymApi api;const UpiScreen({super.key,required this.api});
 @override State<UpiScreen> createState()=>_UpiScreenState();}
class _UpiScreenState extends State<UpiScreen>{
 final vpa=TextEditingController(), payee=TextEditingController();bool initial=false,saving=false;XFile? photo;String? message;
 @override void dispose(){vpa.dispose();payee.dispose();super.dispose();}
 Future<Map<String,dynamic>> load()async{final d=await widget.api.get('/settings/upi');
 if(!initial){vpa.text='${d['upi_vpa']??''}';payee.text='${d['upi_payee']??''}';initial=true;}return d;}
 Future<void> save()async{setState((){saving=true;message=null;});
  try{await widget.api.uploadUpi(vpa.text.trim(),payee.text.trim(),photo);
    if(mounted)setState(()=>message='Saved for this gym only.');}
  catch(e){if(mounted)setState(()=>message=e.toString());}finally{if(mounted)setState(()=>saving=false);}}
 @override Widget build(BuildContext context)=>AsyncScreen(load:load,builder:(d)=>ListView(padding:const EdgeInsets.all(16),children:[
   const SectionTitle('UPI / QR Settings',caption:'Private payment settings for this gym'),const SizedBox(height:16),
   const FieldLabel('UPI ID'),TextField(controller:vpa,readOnly:!widget.api.admin,
      decoration:const InputDecoration(hintText:'yourgym@bank',prefixIcon:Icon(Icons.account_balance_wallet))),
   const SizedBox(height:16),const FieldLabel('PAYEE NAME'),TextField(controller:payee,readOnly:!widget.api.admin,
     decoration:const InputDecoration(prefixIcon:Icon(Icons.store))),const SizedBox(height:16),
   if(d['has_qr_image']==true)...[const FieldLabel('CURRENT UPLOADED QR'),FutureBuilder<Uint8List>(future:widget.api.qrBytes(),
     builder:(context,s)=>s.hasData?Container(alignment:Alignment.center,child:Image.memory(s.data!,width:220)):
      const Text('Loading QR...',style:TextStyle(color:muted))),const SizedBox(height:16)],
   if(widget.api.admin)...[
    OutlinedButton.icon(onPressed:()=>ImagePicker().pickImage(source:ImageSource.gallery).then((x){if(mounted)setState(()=>photo=x);}),
      icon:const Icon(Icons.add_photo_alternate_outlined),label:Text(photo==null?'Upload this gym’s QR':'Selected: ${photo!.name}')),
    const SizedBox(height:12),FilledButton(onPressed:saving?null:save,child:Text(saving?'Saving...':'Save UPI Settings')),
   ] else const Text('Only your Gym Admin may change QR settings.',style:TextStyle(color:muted)),
   if(message!=null)Padding(padding:const EdgeInsets.all(12),child:Text(message!)),
   const SizedBox(height:12),const Text('Payments must be verified manually in the receiving bank app.',style:TextStyle(color:muted,fontSize:12)),
 ]));
}

class AccountScreen extends StatelessWidget {final GymApi api;final Future<void> Function() onLogout;
 const AccountScreen({super.key,required this.api,required this.onLogout});
 @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(16),children:[
   const SectionTitle('Account'),const SizedBox(height:17),tileCard(child:ListTile(leading:const Icon(Icons.verified_user,color:cyan),
      title:Text('${api.identity?['username']}'),subtitle:Text('${api.identity?['role']}'))),
   FilledButton.icon(onPressed:onLogout,icon:const Icon(Icons.logout),label:const Text('Sign out'))
 ]);
}