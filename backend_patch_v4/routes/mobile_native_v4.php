<?php
use Illuminate\Support\Facades\Route;
use App\Http\Controllers\Api\MobileFullController as F;
use App\Http\Middleware\AuthenticateMobileToken as Token;
use App\Http\Middleware\EnsureMobileWorkspace as Workspace;
use App\Http\Middleware\EnsureMobileRole as Role;

// Additive routes: avoids changing the already deployed HRMS web UI, tenancy or migrations.
Route::prefix('mobile/v1')->middleware(Token::class)->group(function(){
    Route::get('/profile',[F::class,'profile']);
    Route::patch('/profile',[F::class,'profile']);
    Route::post('/password/change',[F::class,'changePassword']);
    Route::prefix('super-admin')->middleware(Role::class.':super_admin')->group(function(){
        Route::post('/tenants',[F::class,'createTenant']);
        Route::get('/tenants/{id}',[F::class,'tenant'])->whereNumber('id');
        Route::patch('/tenants/{id}/connection',[F::class,'connection'])->whereNumber('id');
        Route::post('/tenants/{id}/initialize',[F::class,'initialize'])->whereNumber('id');
        Route::patch('/tenants/{id}/active',[F::class,'active'])->whereNumber('id');
    });
    Route::middleware([Workspace::class,Role::class.':employee'])->group(function(){
        Route::get('/performance',[F::class,'performance']);
    });
    Route::middleware([Workspace::class,Role::class.':company_admin,admin,manager,hr'])->group(function(){
        Route::post('/employees',[F::class,'saveEmployee']);
        Route::patch('/employees/{id}',[F::class,'saveEmployee'])->whereNumber('id');
        Route::delete('/employees/{id}',[F::class,'deleteEmployee'])->whereNumber('id');
        Route::post('/employees/{id}/{action}',[F::class,'employeeLogin'])
            ->whereNumber('id')->whereIn('action',['create-login','reset-password']);
        Route::get('/birthdays',[F::class,'birthdays']);
        Route::get('/reports',[F::class,'reports']);
        Route::delete('/leads/{id}',[F::class,'deleteLead'])->whereNumber('id');
        Route::delete('/tasks/{id}',[F::class,'deleteTask'])->whereNumber('id');
    });
});