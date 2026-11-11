<?php
use Illuminate\Support\Facades\Route;
use App\Http\Controllers\Api\MobileAuthController as Auth;
use App\Http\Controllers\Api\MobileWorkspaceController as Workspace;
use App\Http\Controllers\Api\MobileSuperAdminController as SuperAdmin;
use App\Http\Middleware\AuthenticateMobileToken as Token;
use App\Http\Middleware\EnsureMobileWorkspace as WorkspaceAccess;
use App\Http\Middleware\EnsureMobileRole as Role;

Route::prefix('mobile/v1')->group(function () {
    Route::get('/health',fn()=>response()->json(['ok'=>true,'app'=>'RCONSOFT HRMS API','version'=>'1']));
    Route::post('/login',[Auth::class,'login']);
    Route::middleware(Token::class)->group(function () {
        Route::get('/me',[Auth::class,'me']);
        Route::post('/logout',[Auth::class,'logout']);
        Route::get('/subscription',[Workspace::class,'billing'])->middleware(Role::class.':company_admin,admin,hr,manager,employee');
        Route::post('/subscription/request',[Workspace::class,'requestPlan'])->middleware(Role::class.':company_admin,admin');

        Route::prefix('super-admin')->middleware(Role::class.':super_admin')->group(function () {
            Route::get('/dashboard',[SuperAdmin::class,'dashboard']);
            Route::get('/tenants',[SuperAdmin::class,'tenants']);
            Route::get('/subscriptions',[SuperAdmin::class,'requests']);
            Route::post('/subscriptions/{id}/review',[SuperAdmin::class,'review']);
        });

        Route::middleware(WorkspaceAccess::class)->group(function () {
            Route::get('/dashboard',[Workspace::class,'dashboard']);
            Route::get('/tasks',[Workspace::class,'tasks']);
            Route::patch('/tasks/{id}/my-status',[Workspace::class,'updateMyTask'])->middleware(Role::class.':employee');
            Route::get('/attendance',[Workspace::class,'attendance']);
            Route::post('/attendance/{kind}',[Workspace::class,'punch'])->whereIn('kind',['check-in','check-out']);
            Route::get('/leaves',[Workspace::class,'leaves']);
            Route::post('/leaves',[Workspace::class,'requestLeave']);
            Route::middleware(Role::class.':company_admin,admin,hr,manager')->group(function () {
                Route::get('/employees',[Workspace::class,'employees']);
                Route::get('/leads',[Workspace::class,'leads']);
                Route::post('/leads',[Workspace::class,'saveLead']);
                Route::patch('/leads/{id}',[Workspace::class,'saveLead']);
                Route::post('/tasks',[Workspace::class,'saveTask']);
                Route::patch('/tasks/{id}',[Workspace::class,'saveTask']);
                Route::patch('/leaves/{id}/review',[Workspace::class,'approveLeave']);
            });
        });
    });
});

require __DIR__.'/mobile_native_v4.php';