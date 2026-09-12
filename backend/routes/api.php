<?php

use App\Http\Controllers\Api\V1\AcademicYearController;
use App\Http\Controllers\Api\V1\AnnouncementController;
use App\Http\Controllers\Api\V1\AttendanceController;
use App\Http\Controllers\Api\V1\AuthController;
use App\Http\Controllers\Api\V1\CommunicationController;
use App\Http\Controllers\Api\V1\DailyTeachingReportController;
use App\Http\Controllers\Api\V1\DepartmentController;
use App\Http\Controllers\Api\V1\DriverController;
use App\Http\Controllers\Api\V1\HodReportController;
use App\Http\Controllers\Api\V1\HolidayController;
use App\Http\Controllers\Api\V1\InboxController;
use App\Http\Controllers\Api\V1\PasswordResetController;
use App\Http\Controllers\Api\V1\PaymentController;
use App\Http\Controllers\Api\V1\PeriodController;
use App\Http\Controllers\Api\V1\SchoolClassController;
use App\Http\Controllers\Api\V1\SchoolController;
use App\Http\Controllers\Api\V1\StaffAttendanceController;
use App\Http\Controllers\Api\V1\StaffController;
use App\Http\Controllers\Api\V1\StaffLeaveController;
use App\Http\Controllers\Api\V1\StudentController;
use App\Http\Controllers\Api\V1\StudentTransportController;
use App\Http\Controllers\Api\V1\SubjectController;
use App\Http\Controllers\Api\V1\SyllabusProgressController;
use App\Http\Controllers\Api\V1\SyllabusTopicController;
use App\Http\Controllers\Api\V1\TimetableController;
use App\Http\Controllers\Api\V1\TimezoneController;
use App\Http\Controllers\Api\V1\TransportRouteController;
use App\Http\Controllers\Api\V1\TransportTripController;
use App\Http\Controllers\Api\V1\UserController;
use App\Http\Controllers\Api\V1\VehicleController;
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

    // Reference data for the school form's timezone picker.
    Route::get('/timezones', [TimezoneController::class, 'index']);

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
    Route::put('/students/{student}/transport', [StudentTransportController::class, 'assign']);
    Route::delete('/students/{student}/transport', [StudentTransportController::class, 'unassign']);

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

    Route::get('/transport/vehicles', [VehicleController::class, 'index']);
    Route::post('/transport/vehicles', [VehicleController::class, 'store']);
    Route::get('/transport/vehicles/{vehicle}', [VehicleController::class, 'show']);
    Route::patch('/transport/vehicles/{vehicle}', [VehicleController::class, 'update']);
    Route::delete('/transport/vehicles/{vehicle}', [VehicleController::class, 'destroy']);

    Route::get('/transport/drivers', [DriverController::class, 'index']);
    Route::post('/transport/drivers', [DriverController::class, 'store']);
    Route::get('/transport/drivers/{driver}', [DriverController::class, 'show']);
    Route::patch('/transport/drivers/{driver}', [DriverController::class, 'update']);
    Route::delete('/transport/drivers/{driver}', [DriverController::class, 'destroy']);

    Route::get('/transport/routes', [TransportRouteController::class, 'index']);
    Route::post('/transport/routes', [TransportRouteController::class, 'store']);
    Route::get('/transport/routes/{route}', [TransportRouteController::class, 'show']);
    Route::patch('/transport/routes/{route}', [TransportRouteController::class, 'update']);
    Route::delete('/transport/routes/{route}', [TransportRouteController::class, 'destroy']);
    Route::get('/transport/routes/{route}/students', [TransportRouteController::class, 'students']);
    Route::post('/transport/routes/{route}/stops', [TransportRouteController::class, 'storeStop']);
    Route::patch('/transport/stops/{stop}', [TransportRouteController::class, 'updateStop']);
    Route::delete('/transport/stops/{stop}', [TransportRouteController::class, 'destroyStop']);

    Route::get('/transport/trips', [TransportTripController::class, 'index']);
    Route::post('/transport/trips', [TransportTripController::class, 'store']);
    Route::get('/transport/trips/{trip}', [TransportTripController::class, 'show']);
    Route::post('/transport/trips/{trip}/stops/{stop}/reached', [TransportTripController::class, 'reachStop']);
    Route::patch('/transport/trips/{trip}/riders/{student}', [TransportTripController::class, 'updateRider']);
    Route::post('/transport/trips/{trip}/end', [TransportTripController::class, 'end']);
    Route::post('/transport/trips/{trip}/cancel', [TransportTripController::class, 'cancel']);

    // Phase 16 - Communication.
    Route::get('/communication/messages', [CommunicationController::class, 'index']);
    Route::get('/communication/summary', [CommunicationController::class, 'summary']);
    Route::get('/communication/messages/{message}', [CommunicationController::class, 'show']);
    Route::post('/communication/messages/{message}/retry', [CommunicationController::class, 'retry']);
    Route::get('/communication/templates', [CommunicationController::class, 'templates']);
    Route::put('/communication/templates/{event}', [CommunicationController::class, 'updateTemplate']);
    Route::delete('/communication/templates/{event}', [CommunicationController::class, 'resetTemplate']);
    Route::get('/communication/settings', [CommunicationController::class, 'settings']);
    Route::put('/communication/settings', [CommunicationController::class, 'updateSettings']);

    Route::get('/inbox', [InboxController::class, 'index']);
    Route::get('/inbox/unread-count', [InboxController::class, 'unreadCount']);
    Route::post('/inbox/{message}/read', [InboxController::class, 'markRead']);
    Route::post('/inbox/read-all', [InboxController::class, 'markAllRead']);

    // Phase 17 - Announcements.
    Route::get('/announcements', [AnnouncementController::class, 'index']);
    Route::get('/announcements/preview', [AnnouncementController::class, 'preview']);
    Route::post('/announcements', [AnnouncementController::class, 'store']);
    Route::get('/announcements/{announcement}', [AnnouncementController::class, 'show']);
    Route::delete('/announcements/{announcement}', [AnnouncementController::class, 'destroy']);
});
