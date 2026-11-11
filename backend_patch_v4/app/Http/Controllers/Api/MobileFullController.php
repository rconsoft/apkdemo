<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Attendance;
use App\Models\Company;
use App\Models\Employee;
use App\Models\Lead;
use App\Models\LeaveRequest;
use App\Models\SubscriptionRequest;
use App\Models\Task;
use App\Models\User;
use App\Support\SubscriptionGate;
use App\Support\TenantDatabase;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;

/** Optional additive API endpoints for the real Flutter (no WebView) app. */
class MobileFullController extends Controller
{
    private function company(Request $request): int
    {
        return (int) $request->user()->company_id;
    }

    private function profileUser(Request $request): User
    {
        return $request->user();
    }

    private function employee(Request $request): Employee
    {
        $user = $request->user();
        abort_unless($user->employee_id,403,'Employee login is not linked to a profile.');
        return Employee::where('company_id',$user->company_id)->findOrFail($user->employee_id);
    }

    public function profile(Request $request)
    {
        $user=$this->profileUser($request);
        if ($request->isMethod('GET')) {
            return response()->json(['data'=>[ 'id'=>$user->id,'name'=>$user->name,'email'=>$user->email,
                'phone'=>$user->phone,'role'=>$user->role,'company_name'=>$user->company?->name,
                'must_change_password'=>(bool)$user->must_change_password ]]);
        }
        $data=$request->validate([
            'name'=>'required|string|max:120',
            'email'=>['required','email','max:190',Rule::unique('users','email')->ignore($user->id)],
            'phone'=>'nullable|string|max:40',
        ]);
        $user->update($data);
        return response()->json(['message'=>'Profile updated.','data'=>['name'=>$user->name,'email'=>$user->email,'phone'=>$user->phone]]);
    }

    public function changePassword(Request $request)
    {
        $data=$request->validate([
            'current_password'=>'required|string',
            'password'=>'required|string|min:8|confirmed',
        ]);
        $user=$request->user();
        if(!Hash::check($data['current_password'],$user->password)) {
            return response()->json(['message'=>'Current password is incorrect.'],422);
        }
        $user->update(['password'=>Hash::make($data['password']),'must_change_password'=>false]);
        DB::connection('mysql')->table('mobile_api_tokens')->where('user_id',$user->id)
            ->where('id','!=',$request->attributes->get('mobile_token_id'))->delete();
        return response()->json(['message'=>'Password updated. Other mobile sessions revoked.']);
    }

    private function employeeData(Request $request, ?Employee $employee=null): array
    {
        $company=$this->company($request);
        $userId=$employee?->user?->id;
        return $request->validate([
            'employee_code'=>['required','string','max:40',Rule::unique('tenant.employees','employee_code')->where('company_id',$company)->ignore($employee?->id)],
            'first_name'=>'required|string|max:100','last_name'=>'nullable|string|max:100',
            'email'=>['required','email','max:190',Rule::unique('tenant.employees','email')->ignore($employee?->id),Rule::unique('users','email')->ignore($userId)],
            'phone'=>'nullable|string|max:30','department'=>'nullable|string|max:100',
            'designation'=>'nullable|string|max:100','employment_type'=>'required|in:Full-time,Part-time,Contract,Intern',
            'joining_date'=>'nullable|date','date_of_birth'=>'required|date|before_or_equal:today',
            'salary'=>'nullable|numeric|min:0','status'=>'required|in:Active,On Leave,Inactive',
            'manager_name'=>'nullable|string|max:150',
        ]);
    }

    public function saveEmployee(Request $request, ?int $id=null)
    {
        $company=$this->company($request);
        $employee=$id ? Employee::where('company_id',$company)->findOrFail($id) : null;
        if ($employee) $employee->load('user');
        $data=$this->employeeData($request,$employee);
        if ($employee) {
            $employee->update($data);
            if ($employee->user) {
                $employee->user->update(['name'=>$employee->full_name,'email'=>$employee->email,
                    'phone'=>$employee->phone,'is_active'=>$employee->status==='Active']);
            }
            return response()->json(['message'=>'Employee updated.','data'=>$employee->fresh()]);
        }
        // Generate a unique temporary password. It is only returned once to the authorized HR manager.
        $password=Str::password(16);
        $created=null;
        try {
            $created=Employee::create($data+['company_id'=>$company]);
            User::create(['company_id'=>$company,'employee_id'=>$created->id,
                'name'=>$created->full_name,'email'=>$created->email,'phone'=>$created->phone,
                'password'=>$password,'role'=>'employee','is_active'=>$created->status==='Active','must_change_password'=>true]);
        } catch (\Throwable $e) {
            if($created) $created->delete();
            throw $e;
        }
        return response()->json(['message'=>'Employee and login created. Share password securely.',
            'data'=>$created,'temporary_credentials'=>['email'=>$created->email,'password'=>$password]],201);
    }

    public function deleteEmployee(Request $request, int $id)
    {
        $employee=Employee::where('company_id',$this->company($request))->findOrFail($id);
        $user=User::withoutGlobalScopes()->where('company_id',$this->company($request))
            ->where('employee_id',$employee->id)->first();
        if($user) $user->update(['is_active'=>false,'employee_id'=>null]);
        $employee->delete();
        return response()->json(['message'=>'Employee removed; employee login disabled.']);
    }

    public function employeeLogin(Request $request, int $id, string $action)
    {
        abort_unless(in_array($action,['create-login','reset-password'],true),404);
        $employee=Employee::where('company_id',$this->company($request))->findOrFail($id);
        abort_unless($employee->email,422,'Employee must have a work email.');
        $existing=User::withoutGlobalScopes()->where('company_id',$this->company($request))
            ->where('employee_id',$employee->id)->first();
        if($action==='create-login' && $existing) return response()->json(['message'=>'Employee already has a login.'],409);
        if($action==='reset-password' && !$existing) return response()->json(['message'=>'No login exists for this employee.'],404);
        $pass=Str::password(16);
        if($existing) {
            $existing->update(['password'=>Hash::make($pass),'must_change_password'=>true,'is_active'=>$employee->status==='Active']);
            DB::connection('mysql')->table('mobile_api_tokens')->where('user_id',$existing->id)->delete();
        }
        else User::create(['company_id'=>$this->company($request),'employee_id'=>$employee->id,
            'name'=>$employee->full_name,'email'=>$employee->email,'phone'=>$employee->phone,
            'password'=>$pass,'role'=>'employee','is_active'=>$employee->status==='Active','must_change_password'=>true]);
        return response()->json(['message'=>'Temporary password generated; share securely.',
            'temporary_credentials'=>['email'=>$employee->email,'password'=>$pass]]);
    }

    public function birthdays(Request $request)
    {
        $today=Carbon::today();
        $rows=Employee::where('company_id',$this->company($request))
            ->whereNotNull('date_of_birth')->where('status','!=','Inactive')->get()->map(function ($e) use ($today) {
                $dob=$e->date_of_birth;
                $next=$dob->copy()->year($today->year)->startOfDay();
                if($next->lt($today)) $next->addYear();
                return ['id'=>$e->id,'employee_code'=>$e->employee_code,'name'=>$e->full_name,
                    'department'=>$e->department,'date_of_birth'=>$dob->toDateString(),
                    'next_birthday'=>$next->toDateString(),'days_left'=>(int)$today->diffInDays($next),
                    'turning_age'=>$next->year-$dob->year];
            })->sortBy('days_left')->values();
        return response()->json(['data'=>$rows,'today_count'=>$rows->where('days_left',0)->count(),
            'upcoming_30'=>$rows->where('days_left','<=',30)->count()]);
    }

    public function deleteLead(Request $request,int $id)
    {
        Lead::where('company_id',$this->company($request))->findOrFail($id)->delete();
        return response()->json(['message'=>'CRM lead deleted.']);
    }
    public function deleteTask(Request $request,int $id)
    {
        Task::where('company_id',$this->company($request))->findOrFail($id)->delete();
        return response()->json(['message'=>'Task deleted.']);
    }

    private function period(Request $request): array
    {
        $data=$request->validate(['from'=>'nullable|date','to'=>'nullable|date|after_or_equal:from']);
        $from=$data['from']??now()->startOfMonth()->toDateString();
        $to=$data['to']??now()->toDateString();
        abort_if(Carbon::parse($from)->diffInDays(Carbon::parse($to))>366,422,'Report range cannot exceed one year.');
        return [$from,$to];
    }

    public function reports(Request $request)
    {
        [$from,$to]=$this->period($request);$c=$this->company($request);
        $attendance=Attendance::with('employee')->where('company_id',$c)->whereBetween('work_date',[$from,$to]);
        $rows=(clone $attendance)->orderByDesc('work_date')->limit(500)->get()->map(fn($a)=>[
            'work_date'=>$a->work_date?->toDateString(),'employee_code'=>$a->employee?->employee_code,
            'employee_name'=>$a->employee?->full_name,'check_in'=>$a->check_in?->toDateTimeString(),
            'check_out'=>$a->check_out?->toDateTimeString(),'status'=>$a->status,
        ]);
        return response()->json(['from'=>$from,'to'=>$to,'summary'=>[
            'employees'=>Employee::where('company_id',$c)->count(),
            'active_employees'=>Employee::where('company_id',$c)->where('status','Active')->count(),
            'attendance'=>(clone $attendance)->count(),
            'leaves'=>LeaveRequest::where('company_id',$c)->whereBetween('start_date',[$from,$to])->count(),
            'leads'=>Lead::where('company_id',$c)->whereBetween('created_at',[$from.' 00:00:00',$to.' 23:59:59'])->count(),
        ],'attendance_rows'=>$rows]);
    }

    public function performance(Request $request)
    {
        $employee=$this->employee($request);$c=$this->company($request);
        $tasks=Task::where('company_id',$c)->where(function($q)use($employee){
            $q->where('assigned_to',$employee->employee_code)->orWhere('assigned_to',$employee->full_name)
                ->orWhere('assigned_to',$employee->email);
        });
        return response()->json(['employee'=>['id'=>$employee->id,'name'=>$employee->full_name,
                'code'=>$employee->employee_code,'department'=>$employee->department],
            'summary'=>['total_tasks'=>(clone $tasks)->count(),
                'completed_tasks'=>(clone $tasks)->where('status','Completed')->count(),
                'attendance_days'=>Attendance::where('company_id',$c)->where('employee_id',$employee->id)
                    ->whereMonth('work_date',now()->month)->whereYear('work_date',now()->year)->count()],
            'tasks'=>$tasks->latest()->limit(50)->get()]);
    }

    public function tenant(Request $request,int $id)
    {
        $company=Company::findOrFail($id);
        return response()->json(['data'=>[
            'id'=>$company->id,'name'=>$company->name,'slug'=>$company->slug,
            'email'=>$company->email,'phone'=>$company->phone,'address'=>$company->address,
            'is_active'=>$company->is_active,'db_host'=>$company->db_host,'db_port'=>$company->db_port,
            'db_database'=>$company->db_database,'db_username'=>$company->db_username,
            'database_ready_at'=>$company->database_ready_at,
            'trial_starts_at'=>$company->trial_starts_at,'trial_ends_at'=>$company->trial_ends_at,
            'subscription'=>app(SubscriptionGate::class)->status($company),
            'users'=>User::withoutGlobalScopes()->where('company_id',$id)
                ->get(['id','name','email','role','is_active']),
            'requests'=>SubscriptionRequest::where('company_id',$id)->latest()->limit(30)->get(),
        ]]);
    }

    public function createTenant(Request $request)
    {
        $data=$request->validate([
            'name'=>'required|string|max:150',
            'slug'=>['required','string','max:80','regex:/^[a-z0-9-]+$/','unique:companies,slug'],
            'email'=>'nullable|email|max:190','phone'=>'nullable|string|max:40',
            'db_host'=>'required|string|max:150','db_port'=>'required|integer|between:1,65535',
            'db_database'=>['required','string','max:64','regex:/^[a-zA-Z0-9_]+$/','unique:companies,db_database'],
            'db_username'=>'required|string|max:120','db_password'=>'required|string|max:255',
            'admin_name'=>'required|string|max:120','admin_email'=>['required','email','max:190','unique:users,email'],
            'admin_password'=>'required|string|min:12|confirmed',
        ]);
        abort_if($data['db_database']===config('database.connections.mysql.database'),422,'Cannot reuse central database.');
        $company=DB::connection('mysql')->transaction(function()use($data){
            $company=Company::create(['name'=>$data['name'],'slug'=>$data['slug'],
                'email'=>$data['email']??null,'phone'=>$data['phone']??null,'is_active'=>true,
                'db_host'=>$data['db_host'],'db_port'=>$data['db_port'],
                'db_database'=>$data['db_database'],'db_username'=>$data['db_username'],
                'db_password'=>$data['db_password']]);
            User::create(['company_id'=>$company->id,'name'=>$data['admin_name'],
                'email'=>$data['admin_email'],'password'=>$data['admin_password'],
                'role'=>'company_admin','is_active'=>true]);
            return $company;
        });
        return response()->json(['message'=>'Tenant created. Initialize its pre-created MySQL database.',
            'data'=>['id'=>$company->id,'name'=>$company->name,'slug'=>$company->slug]],201);
    }

    public function connection(Request $request,int $id)
    {
        $company=Company::findOrFail($id);
        $data=$request->validate([
            'db_host'=>'required|string|max:150','db_port'=>'required|integer|between:1,65535',
            'db_database'=>['required','string','max:64','regex:/^[a-zA-Z0-9_]+$/',Rule::unique('companies','db_database')->ignore($company->id)],
            'db_username'=>'required|string|max:120','db_password'=>'nullable|string|max:255',
        ]);
        abort_if($data['db_database']===config('database.connections.mysql.database'),422,'Cannot reuse central database.');
        $changed=$company->db_host!==$data['db_host'] || $company->db_database!==$data['db_database']
            || $company->db_username!==$data['db_username'] || (int)$company->db_port!==(int)$data['db_port']
            || !empty($data['db_password']);
        if(empty($data['db_password']))unset($data['db_password']);
        if($changed)$data['database_ready_at']=null;
        $company->update($data);
        return response()->json(['message'=>'Connection settings saved. Re-initialize if changed.']);
    }

    public function initialize(Request $request,int $id)
    {
        $company=Company::findOrFail($id);
        abort_unless($company->db_database,422,'Tenant database must be configured first.');
        try {
            app(TenantDatabase::class)->activate($company);
            DB::connection('tenant')->getPdo();
            $code=Artisan::call('migrate',['--database'=>'tenant','--path'=>'database/migrations/tenant',
                '--force'=>true,'--no-interaction'=>true]);
            if($code!==0)throw new \RuntimeException('Tenant migration failed.');
            $company->forceFill(['database_ready_at'=>now()])->save();
            return response()->json(['message'=>'Tenant database initialized successfully.']);
        } catch (\Throwable $e) {
            Log::error('Mobile tenant initialization failed',['tenant_id'=>$id,'exception'=>$e]);
            return response()->json(['message'=>'Database initialization failed. Check MySQL permissions and Laravel logs.'],500);
        }
    }

    public function active(Request $request,int $id)
    {
        $data=$request->validate(['is_active'=>'required|boolean']);
        $company=Company::findOrFail($id);
        $company->update(['is_active'=>(bool)$data['is_active']]);
        return response()->json(['message'=>$company->is_active?'Tenant activated.':'Tenant suspended.']);
    }
}