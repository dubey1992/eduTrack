<?php

use App\Http\Controllers\Api\V1\AcademicYearController;
use App\Http\Controllers\Api\V1\AttendanceController;
use App\Http\Controllers\Api\V1\AuthController;
use App\Http\Controllers\Api\V1\DailyTeachingReportController;
use App\Http\Controllers\Api\V1\DepartmentController;
use App\Http\Controllers\Api\V1\HodReportController;
use App\Http\Controllers\Api\V1\HolidayController;
use App\Http\Controllers\Api\V1\PasswordResetController;
use App\Http\Controllers\Api\V1\PaymentController;
use App\Http\Controllers\Api\V1\PeriodController;
use App\Http\Controllers\Api\V1\SchoolClassController;
use App\Http\Controllers\Api\V1\SchoolController;
use App\Http\Controllers\Api\V1\StaffAttendanceController;
use App\Http\Controllers\Api\V1\StaffController;
use App\Http\Controllers\Api\V1\StaffLeaveController;
use App\Http\Controllers\Api\V1\StudentController;
use App\Http\Controllers\Api\V1\SubjectController;
use App\Http\Controllers\Api\V1\SyllabusProgressController;
use App\Http\Controllers\Api\V1\SyllabusTopicController;
use App\Http\Controllers\Api\V1\TimetableController;
use App\Http\Controllers\Api\V1\UserController;
use Illuminate\Support\Facades\Route;

// Mounted under /api/v1 (see bootstrap/app.php apiPrefix).

Route::post('/auth/login', [AuthController::class, 'login']);
Route::post('/auth/forgot-password', [PasswordResetController::class, 'forgot']);
Route::post('/auth/reset-password', [PasswordResetController::class, 'reset']);

Route::middleware('auth:sanctum')->group(function () {
    Route::post('/auth/logout', [AuthController::class, 'logout']);
    Route::get('/me', [AuthController::class, 'me']);

    Route::get('/users', [UserController::class, 'index']);
    Route::post('/users', [UserController::class, 'store']);
    Route::get('/users/{user}', [UserController::class, 'show']);
    Route::patch('/users/{user}', [UserController::class, 'update']);
    Route::patch('/users/{user}/activate', [UserController::class, 'activate']);
    Route::patch('/users/{user}/deactivate', [UserController::class, 'deactivate']);

    Route::get('/schools', [SchoolController::class, 'index']);
    Route::post('/schools', [SchoolController::class, 'store']);
    Route::get('/schools/{school}', [SchoolController::class, 'show']);
    Route::patch('/schools/{school}', [SchoolController::class, 'update']);
    Route::patch('/schools/{school}/activate', [SchoolController::class, 'activate']);
    Route::patch('/schools/{school}/deactivate', [SchoolController::class, 'deactivate']);

    Route::get('/payments/summary', [PaymentController::class, 'summary']);
    Route::get('/payments', [PaymentController::class, 'index']);
    Route::post('/payments', [PaymentController::class, 'store']);
    Route::get('/payments/{payment}', [PaymentController::class, 'show']);
    Route::patch('/payments/{payment}', [PaymentController::class, 'update']);

    Route::get('/academic-years', [AcademicYearController::class, 'index']);
    Route::post('/academic-years', [AcademicYearController::class, 'store']);
    Route::get('/academic-years/{academicYear}', [AcademicYearController::class, 'show']);
    Route::patch('/academic-years/{academicYear}', [AcademicYearController::class, 'update']);
    Route::patch('/academic-years/{academicYear}/set-current', [AcademicYearController::class, 'setCurrent']);
    Route::delete('/academic-years/{academicYear}', [AcademicYearController::class, 'destroy']);

    Route::get('/departments', [DepartmentController::class, 'index']);
    Route::post('/departments', [DepartmentController::class, 'store']);
    Route::get('/departments/{department}', [DepartmentController::class, 'show']);
    Route::patch('/departments/{department}', [DepartmentController::class, 'update']);
    Route::delete('/departments/{department}', [DepartmentController::class, 'destroy']);

    Route::get('/subjects', [SubjectController::class, 'index']);
    Route::post('/subjects', [SubjectController::class, 'store']);
    Route::get('/subjects/{subject}', [SubjectController::class, 'show']);
    Route::patch('/subjects/{subject}', [SubjectController::class, 'update']);
    Route::delete('/subjects/{subject}', [SubjectController::class, 'destroy']);

    Route::get('/classes', [SchoolClassController::class, 'index']);
    Route::post('/classes', [SchoolClassController::class, 'store']);
    Route::get('/classes/{schoolClass}', [SchoolClassController::class, 'show']);
    Route::patch('/classes/{schoolClass}', [SchoolClassController::class, 'update']);
    Route::delete('/classes/{schoolClass}', [SchoolClassController::class, 'destroy']);
    Route::post('/classes/{schoolClass}/sections', [SchoolClassController::class, 'addSection']);
    Route::patch('/sections/{section}', [SchoolClassController::class, 'updateSection']);
    Route::delete('/sections/{section}', [SchoolClassController::class, 'deleteSection']);

    Route::get('/staff', [StaffController::class, 'index']);
    Route::post('/staff', [StaffController::class, 'store']);
    Route::get('/staff/{staffProfile}', [StaffController::class, 'show']);
    Route::patch('/staff/{staffProfile}', [StaffController::class, 'update']);

    Route::get('/students', [StudentController::class, 'index']);
    Route::post('/students', [StudentController::class, 'store']);
    Route::get('/students/{student}', [StudentController::class, 'show']);
    Route::patch('/students/{student}', [StudentController::class, 'update']);
    Route::patch('/students/{student}/activate', [StudentController::class, 'activate']);
    Route::patch('/students/{student}/deactivate', [StudentController::class, 'deactivate']);

    Route::get('/attendance/register', [AttendanceController::class, 'register']);
    Route::get('/attendance', [AttendanceController::class, 'index']);
    Route::post('/attendance', [AttendanceController::class, 'store']);
    Route::patch('/attendance', [AttendanceController::class, 'update']);

    Route::get('/staff-attendance/register', [StaffAttendanceController::class, 'register']);
    Route::get('/staff-attendance', [StaffAttendanceController::class, 'index']);
    Route::post('/staff-attendance', [StaffAttendanceController::class, 'store']);
    Route::patch('/staff-attendance', [StaffAttendanceController::class, 'update']);

    Route::get('/leaves/summary', [StaffLeaveController::class, 'summary']);
    Route::get('/leaves', [StaffLeaveController::class, 'index']);
    Route::post('/leaves', [StaffLeaveController::class, 'store']);
    Route::patch('/leaves/{leave}/approve', [StaffLeaveController::class, 'approve']);
    Route::patch('/leaves/{leave}/reject', [StaffLeaveController::class, 'reject']);

    Route::get('/periods', [PeriodController::class, 'index']);
    Route::post('/periods', [PeriodController::class, 'store']);
    Route::patch('/periods/{period}', [PeriodController::class, 'update']);
    Route::delete('/periods/{period}', [PeriodController::class, 'destroy']);

    Route::get('/timetable', [TimetableController::class, 'grid']);
    Route::post('/timetable', [TimetableController::class, 'upsert']);
    Route::delete('/timetable/{entry}', [TimetableController::class, 'destroy']);

    Route::get('/teaching-reports/summary', [DailyTeachingReportController::class, 'summary']);
    Route::get('/teaching-reports', [DailyTeachingReportController::class, 'index']);
    Route::post('/teaching-reports', [DailyTeachingReportController::class, 'store']);
    Route::patch('/teaching-reports/{report}/review', [DailyTeachingReportController::class, 'review']);

    Route::get('/syllabus-topics', [SyllabusTopicController::class, 'index']);
    Route::post('/syllabus-topics', [SyllabusTopicController::class, 'store']);
    Route::patch('/syllabus-topics/{syllabusTopic}', [SyllabusTopicController::class, 'update']);
    Route::delete('/syllabus-topics/{syllabusTopic}', [SyllabusTopicController::class, 'destroy']);

    Route::get('/syllabus-progress', [SyllabusProgressController::class, 'index']);
    Route::patch('/syllabus-progress', [SyllabusProgressController::class, 'update']);

    Route::get('/hod/department-report', [HodReportController::class, 'departmentReport']);

    Route::get('/holidays', [HolidayController::class, 'index']);
    Route::post('/holidays', [HolidayController::class, 'store']);
    Route::get('/holidays/{holiday}', [HolidayController::class, 'show']);
    Route::patch('/holidays/{holiday}', [HolidayController::class, 'update']);
    Route::delete('/holidays/{holiday}', [HolidayController::class, 'destroy']);
});
