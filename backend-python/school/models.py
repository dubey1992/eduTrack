"""The tables, described - not owned.

Every one of these already exists. Laravel's migrations created them, and M1
proved the PostgreSQL schema identical to MySQL's across 40 tables and 399
columns, so there is nothing here for Django to build. `managed = False` on all
of them says exactly that: Django reads and writes rows, and the database's own
constraints remain the authority on shape.

Which is also why every relation is DO_NOTHING. The foreign keys carry their
own ON DELETE rules, set by the migrations and enforced by PostgreSQL;
restating them here would mean keeping the same decision in two places and
finding out they disagree on the day they do. Django is told not to
second-guess the database.

Generated from `manage.py inspectdb` against the real database and then
corrected: framework tables dropped, because Laravel owns its own queue, cache
and sessions and this backend will grow its own; classes named the way a person
would name them rather than after the table.

One correction is easy to undo by accident and worth naming here. Every
timestamp is a `UtcDateTimeField`, not a plain `DateTimeField`, because these
columns are `timestamp without time zone` holding UTC instants and Django
would otherwise hand back a naive datetime that the next `.astimezone()` reads
as machine-local. That cost five and a half hours on every instant the API
returned, with every test passing. See school/fields.py before changing one
back.

`manage.py check_models` is what proves this file still matches the tables. It
reads a row from each and touches every field, because the failure mode here is
a column that does not exist and is never selected.

The day this backend takes over is the day `managed` changes - deliberately, in
a commit of its own, not as a side effect of something else.
"""

from django.db import models

from .enums import StudentStatus, UserStatus
from .fields import UtcDateTimeField

class AcademicYear(models.Model):
    id = models.BigAutoField(primary_key=True)
    school = models.ForeignKey('School', models.DO_NOTHING)
    name = models.CharField(max_length=50)
    start_date = models.DateField()
    end_date = models.DateField()
    is_current = models.BooleanField()
    created_at = UtcDateTimeField(blank=True, null=True)
    updated_at = UtcDateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'academic_years'
        unique_together = (('school', 'name'),)

class Announcement(models.Model):
    id = models.BigAutoField(primary_key=True)
    school = models.ForeignKey('School', models.DO_NOTHING)
    title = models.CharField(max_length=150)
    body = models.TextField()
    audience_type = models.CharField(max_length=30)
    audience_id = models.BigIntegerField(blank=True, null=True)
    audience_label = models.CharField(max_length=120)
    channels = models.CharField(max_length=20)
    expires_at = models.DateField(blank=True, null=True)
    published_by = models.ForeignKey('User', models.DO_NOTHING, db_column='published_by', blank=True, null=True)
    published_at = UtcDateTimeField()
    recipients_count = models.IntegerField()
    sms_count = models.IntegerField()
    in_app_count = models.IntegerField()
    deleted_at = UtcDateTimeField(blank=True, null=True)
    created_at = UtcDateTimeField(blank=True, null=True)
    updated_at = UtcDateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'announcements'

class Attendance(models.Model):
    id = models.BigAutoField(primary_key=True)
    school = models.ForeignKey('School', models.DO_NOTHING)
    academic_year = models.ForeignKey(AcademicYear, models.DO_NOTHING)
    class_section = models.ForeignKey('ClassSection', models.DO_NOTHING)
    student = models.ForeignKey('Student', models.DO_NOTHING)
    attendance_date = models.DateField()
    status = models.CharField(max_length=255)
    remarks = models.CharField(max_length=255, blank=True, null=True)
    marked_by = models.ForeignKey('User', models.DO_NOTHING, db_column='marked_by', blank=True, null=True)
    created_at = UtcDateTimeField(blank=True, null=True)
    updated_at = UtcDateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'attendances'
        unique_together = (('class_section', 'student', 'attendance_date'),)

class ClassSection(models.Model):
    id = models.BigAutoField(primary_key=True)
    school_class = models.ForeignKey('SchoolClass', models.DO_NOTHING)
    name = models.CharField(max_length=10)
    room_number = models.CharField(max_length=20, blank=True, null=True)
    class_teacher = models.ForeignKey('User', models.DO_NOTHING, blank=True, null=True)
    created_at = UtcDateTimeField(blank=True, null=True)
    updated_at = UtcDateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'class_sections'
        unique_together = (('school_class', 'name'),)

class CommunicationSetting(models.Model):
    id = models.BigAutoField(primary_key=True)
    school = models.OneToOneField('School', models.DO_NOTHING)
    sms_enabled = models.BooleanField()
    attendance_alerts = models.CharField(max_length=20)
    transport_alerts_enabled = models.BooleanField()
    leave_alerts_enabled = models.BooleanField()
    provider = models.CharField(max_length=50)
    sender_id = models.CharField(max_length=20, blank=True, null=True)
    created_at = UtcDateTimeField(blank=True, null=True)
    updated_at = UtcDateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'communication_settings'

class DailyTeachingReport(models.Model):
    id = models.BigAutoField(primary_key=True)
    school = models.ForeignKey('School', models.DO_NOTHING)
    timetable_entry = models.ForeignKey('TimetableEntry', models.DO_NOTHING)
    teacher = models.ForeignKey('User', models.DO_NOTHING)
    report_date = models.DateField()
    topic_taught = models.CharField(max_length=255)
    homework = models.CharField(max_length=500, blank=True, null=True)
    remarks = models.CharField(max_length=500, blank=True, null=True)
    reviewed_by = models.ForeignKey('User', models.DO_NOTHING, db_column='reviewed_by', related_name='dailyteachingreports_reviewed_by_set', blank=True, null=True)
    reviewed_at = UtcDateTimeField(blank=True, null=True)
    created_at = UtcDateTimeField(blank=True, null=True)
    updated_at = UtcDateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'daily_teaching_reports'
        unique_together = (('timetable_entry', 'report_date'),)

class Department(models.Model):
    id = models.BigAutoField(primary_key=True)
    school = models.ForeignKey('School', models.DO_NOTHING)
    name = models.CharField(max_length=100)
    hod_user = models.ForeignKey('User', models.DO_NOTHING, blank=True, null=True)
    created_at = UtcDateTimeField(blank=True, null=True)
    updated_at = UtcDateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'departments'
        unique_together = (('school', 'name'),)

class Driver(models.Model):
    id = models.BigAutoField(primary_key=True)
    school = models.ForeignKey('School', models.DO_NOTHING)
    name = models.CharField(max_length=150)
    mobile = models.CharField(max_length=20, blank=True, null=True)
    licence_number = models.CharField(max_length=50)
    licence_expiry = models.DateField(blank=True, null=True)
    status = models.CharField(max_length=20)
    created_at = UtcDateTimeField(blank=True, null=True)
    updated_at = UtcDateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'drivers'
        unique_together = (('school', 'licence_number'),)

class EarlyAccessRequest(models.Model):
    id = models.BigAutoField(primary_key=True)
    school_name = models.CharField(max_length=150)
    contact_name = models.CharField(max_length=150)
    contact_role = models.CharField(max_length=100, blank=True, null=True)
    email = models.CharField(max_length=255)
    phone = models.CharField(max_length=20)
    city = models.CharField(max_length=100)
    country = models.CharField(max_length=100)
    expected_students = models.IntegerField(blank=True, null=True)
    current_software = models.CharField(max_length=150, blank=True, null=True)
    message = models.TextField(blank=True, null=True)
    status = models.CharField(max_length=20)
    notes = models.TextField(blank=True, null=True)
    converted_school = models.ForeignKey('School', models.DO_NOTHING, blank=True, null=True)
    reviewed_by = models.ForeignKey('User', models.DO_NOTHING, db_column='reviewed_by', blank=True, null=True)
    reviewed_at = UtcDateTimeField(blank=True, null=True)
    created_at = UtcDateTimeField(blank=True, null=True)
    updated_at = UtcDateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'early_access_requests'

class Holiday(models.Model):
    id = models.BigAutoField(primary_key=True)
    school = models.ForeignKey('School', models.DO_NOTHING)
    name = models.CharField(max_length=100)
    type = models.CharField(max_length=20)
    start_date = models.DateField()
    end_date = models.DateField()
    created_at = UtcDateTimeField(blank=True, null=True)
    updated_at = UtcDateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'holidays'

class Message(models.Model):
    id = models.BigAutoField(primary_key=True)
    school = models.ForeignKey('School', models.DO_NOTHING)
    event = models.CharField(max_length=50)
    category = models.CharField(max_length=30)
    channel = models.CharField(max_length=20)
    recipient_name = models.CharField(max_length=150)
    recipient_mobile = models.CharField(max_length=20, blank=True, null=True)
    user = models.ForeignKey('User', models.DO_NOTHING, blank=True, null=True)
    student = models.ForeignKey('Student', models.DO_NOTHING, blank=True, null=True)
    student_name = models.CharField(max_length=150, blank=True, null=True)
    body = models.TextField()
    status = models.CharField(max_length=20)
    provider = models.CharField(max_length=50, blank=True, null=True)
    provider_message_id = models.CharField(max_length=100, blank=True, null=True)
    failure_reason = models.CharField(max_length=255, blank=True, null=True)
    created_by = models.ForeignKey('User', models.DO_NOTHING, db_column='created_by', related_name='messages_created_by_set', blank=True, null=True)
    sent_at = UtcDateTimeField(blank=True, null=True)
    read_at = UtcDateTimeField(blank=True, null=True)
    created_at = UtcDateTimeField(blank=True, null=True)
    updated_at = UtcDateTimeField(blank=True, null=True)
    announcement = models.ForeignKey(Announcement, models.DO_NOTHING, blank=True, null=True)
    subject = models.CharField(max_length=150, blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'messages'

class MessageTemplate(models.Model):
    id = models.BigAutoField(primary_key=True)
    school = models.ForeignKey('School', models.DO_NOTHING)
    event = models.CharField(max_length=50)
    body = models.TextField()
    is_active = models.BooleanField()
    updated_by = models.ForeignKey('User', models.DO_NOTHING, db_column='updated_by', blank=True, null=True)
    created_at = UtcDateTimeField(blank=True, null=True)
    updated_at = UtcDateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'message_templates'
        unique_together = (('school', 'event'),)

class Payment(models.Model):
    id = models.BigAutoField(primary_key=True)
    school = models.ForeignKey('School', models.DO_NOTHING)
    payment_type = models.CharField(max_length=255)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    currency_code = models.CharField(max_length=3)
    payment_date = models.DateField()
    payment_mode = models.CharField(max_length=255)
    reference_number = models.CharField(max_length=255, blank=True, null=True)
    notes = models.TextField(blank=True, null=True)
    status = models.CharField(max_length=255)
    created_by = models.ForeignKey('User', models.DO_NOTHING, db_column='created_by')
    created_at = UtcDateTimeField(blank=True, null=True)
    updated_at = UtcDateTimeField(blank=True, null=True)
    paid_amount = models.DecimalField(max_digits=12, decimal_places=2)
    receipt_sent_at = UtcDateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'payments'

class Period(models.Model):
    id = models.BigAutoField(primary_key=True)
    school = models.ForeignKey('School', models.DO_NOTHING)
    period_number = models.SmallIntegerField()
    start_time = models.TimeField()
    end_time = models.TimeField()
    created_at = UtcDateTimeField(blank=True, null=True)
    updated_at = UtcDateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'periods'
        unique_together = (('school', 'period_number'),)

class PersonalAccessToken(models.Model):
    """The one framework table this backend describes.

    M7 dropped every table Laravel's framework owns - queue, cache, sessions -
    because this backend will grow its own. This one is the exception, and on
    purpose: it is where a signed-in session lives, and both backends have to
    be able to read the same one or a cutover signs everybody out. See
    school/tokens.py, which issues rows Sanctum accepts and accepts rows
    Sanctum issued.

    `tokenable` is a Laravel polymorphic relation, not a foreign key, so it
    stays as the two plain columns the database actually has rather than
    being dressed up as a Django GenericForeignKey that nothing would use.
    """

    id = models.BigAutoField(primary_key=True)
    tokenable_type = models.CharField(max_length=255)
    tokenable_id = models.BigIntegerField()
    name = models.TextField()
    token = models.CharField(unique=True, max_length=64)
    abilities = models.TextField(blank=True, null=True)
    last_used_at = UtcDateTimeField(blank=True, null=True)
    expires_at = UtcDateTimeField(blank=True, null=True)
    created_at = UtcDateTimeField(blank=True, null=True)
    updated_at = UtcDateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'personal_access_tokens'

class School(models.Model):
    id = models.BigAutoField(primary_key=True)
    name = models.CharField(max_length=255)
    registration_number = models.CharField(max_length=255, blank=True, null=True)
    email = models.CharField(unique=True, max_length=255)
    phone = models.CharField(max_length=255)
    address = models.CharField(max_length=255)
    city = models.CharField(max_length=255)
    state = models.CharField(max_length=255)
    country = models.CharField(max_length=255)
    postal_code = models.CharField(max_length=255)
    currency_code = models.CharField(max_length=3)
    logo_url = models.CharField(max_length=255, blank=True, null=True)
    status = models.CharField(max_length=255)
    created_at = UtcDateTimeField(blank=True, null=True)
    updated_at = UtcDateTimeField(blank=True, null=True)
    timezone = models.CharField(max_length=64)
    latitude = models.DecimalField(max_digits=10, decimal_places=7, blank=True, null=True)
    longitude = models.DecimalField(max_digits=10, decimal_places=7, blank=True, null=True)
    parent_school = models.ForeignKey('self', models.DO_NOTHING, blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'schools'

    def is_branch(self) -> bool:
        return self.parent_school_id is not None

class SchoolClass(models.Model):
    id = models.BigAutoField(primary_key=True)
    school = models.ForeignKey('School', models.DO_NOTHING)
    academic_year = models.ForeignKey(AcademicYear, models.DO_NOTHING)
    name = models.CharField(max_length=50)
    level = models.SmallIntegerField()
    created_at = UtcDateTimeField(blank=True, null=True)
    updated_at = UtcDateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'school_classes'
        unique_together = (('academic_year', 'name'),)

class StaffAttendance(models.Model):
    id = models.BigAutoField(primary_key=True)
    school = models.ForeignKey(School, models.DO_NOTHING)
    staff_profile = models.ForeignKey('StaffProfile', models.DO_NOTHING)
    attendance_date = models.DateField()
    status = models.CharField(max_length=255)
    check_in = models.TimeField(blank=True, null=True)
    check_out = models.TimeField(blank=True, null=True)
    remarks = models.CharField(max_length=255, blank=True, null=True)
    marked_by = models.ForeignKey('User', models.DO_NOTHING, db_column='marked_by', blank=True, null=True)
    created_at = UtcDateTimeField(blank=True, null=True)
    updated_at = UtcDateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'staff_attendances'
        unique_together = (('staff_profile', 'attendance_date'),)

class StaffLeave(models.Model):
    id = models.BigAutoField(primary_key=True)
    school = models.ForeignKey(School, models.DO_NOTHING)
    staff_profile = models.ForeignKey('StaffProfile', models.DO_NOTHING)
    leave_type = models.CharField(max_length=255)
    start_date = models.DateField()
    end_date = models.DateField()
    reason = models.CharField(max_length=500)
    status = models.CharField(max_length=255)
    applied_by = models.ForeignKey('User', models.DO_NOTHING, db_column='applied_by')
    reviewed_by = models.ForeignKey('User', models.DO_NOTHING, db_column='reviewed_by', related_name='staffleaves_reviewed_by_set', blank=True, null=True)
    review_remarks = models.CharField(max_length=500, blank=True, null=True)
    created_at = UtcDateTimeField(blank=True, null=True)
    updated_at = UtcDateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'staff_leaves'

class StaffProfile(models.Model):
    id = models.BigAutoField(primary_key=True)
    user = models.OneToOneField('User', models.DO_NOTHING)
    school = models.ForeignKey(School, models.DO_NOTHING)
    employee_id = models.CharField(max_length=30)
    department = models.ForeignKey(Department, models.DO_NOTHING, blank=True, null=True)
    designation = models.CharField(max_length=100, blank=True, null=True)
    joining_date = models.DateField()
    address = models.TextField(blank=True, null=True)
    created_at = UtcDateTimeField(blank=True, null=True)
    updated_at = UtcDateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'staff_profiles'
        unique_together = (('school', 'employee_id'),)

class Student(models.Model):
    id = models.BigAutoField(primary_key=True)
    school = models.ForeignKey(School, models.DO_NOTHING)
    class_section = models.ForeignKey(ClassSection, models.DO_NOTHING, blank=True, null=True)
    admission_number = models.CharField(max_length=30)
    first_name = models.CharField(max_length=100)
    last_name = models.CharField(max_length=100)
    roll_number = models.CharField(max_length=20, blank=True, null=True)
    guardian_name = models.CharField(max_length=150)
    guardian_mobile = models.CharField(max_length=20, blank=True, null=True)
    address = models.TextField(blank=True, null=True)
    status = models.CharField(max_length=255)
    created_at = UtcDateTimeField(blank=True, null=True)
    updated_at = UtcDateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'students'
        unique_together = (('school', 'admission_number'),)

    @property
    def name(self) -> str:
        return f"{self.first_name} {self.last_name}".strip()

    def is_active(self) -> bool:
        return self.status == StudentStatus.ACTIVE

class StudentTransportAssignment(models.Model):
    id = models.BigAutoField(primary_key=True)
    school = models.ForeignKey(School, models.DO_NOTHING)
    student = models.OneToOneField('Student', models.DO_NOTHING)
    route = models.ForeignKey('TransportRoute', models.DO_NOTHING)
    transport_stop = models.ForeignKey('TransportStop', models.DO_NOTHING)
    created_at = UtcDateTimeField(blank=True, null=True)
    updated_at = UtcDateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'student_transport_assignments'

class Subject(models.Model):
    id = models.BigAutoField(primary_key=True)
    school = models.ForeignKey(School, models.DO_NOTHING)
    department = models.ForeignKey(Department, models.DO_NOTHING)
    code = models.CharField(max_length=20)
    name = models.CharField(max_length=100)
    min_class_level = models.SmallIntegerField()
    max_class_level = models.SmallIntegerField()
    lead_teacher = models.ForeignKey('User', models.DO_NOTHING, blank=True, null=True)
    created_at = UtcDateTimeField(blank=True, null=True)
    updated_at = UtcDateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'subjects'
        unique_together = (('school', 'code'),)

class SyllabusTopic(models.Model):
    id = models.BigAutoField(primary_key=True)
    school = models.ForeignKey(School, models.DO_NOTHING)
    subject = models.ForeignKey(Subject, models.DO_NOTHING)
    title = models.CharField(max_length=255)
    sequence_number = models.IntegerField()
    created_at = UtcDateTimeField(blank=True, null=True)
    updated_at = UtcDateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'syllabus_topics'
        unique_together = (('subject', 'sequence_number'),)

class SyllabusTopicProgress(models.Model):
    id = models.BigAutoField(primary_key=True)
    school = models.ForeignKey(School, models.DO_NOTHING)
    syllabus_topic = models.ForeignKey('SyllabusTopic', models.DO_NOTHING)
    class_section = models.ForeignKey(ClassSection, models.DO_NOTHING)
    completed_by = models.ForeignKey('User', models.DO_NOTHING, db_column='completed_by')
    completed_at = UtcDateTimeField()
    created_at = UtcDateTimeField(blank=True, null=True)
    updated_at = UtcDateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'syllabus_topic_progress'
        unique_together = (('syllabus_topic', 'class_section'),)

class TimetableEntry(models.Model):
    id = models.BigAutoField(primary_key=True)
    school = models.ForeignKey(School, models.DO_NOTHING)
    class_section = models.ForeignKey(ClassSection, models.DO_NOTHING)
    period = models.ForeignKey(Period, models.DO_NOTHING)
    day_of_week = models.CharField(max_length=255)
    subject = models.ForeignKey(Subject, models.DO_NOTHING)
    teacher = models.ForeignKey('User', models.DO_NOTHING)
    created_at = UtcDateTimeField(blank=True, null=True)
    updated_at = UtcDateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'timetable_entries'
        unique_together = (('class_section', 'period', 'day_of_week'),)

class TransportRoute(models.Model):
    id = models.BigAutoField(primary_key=True)
    school = models.ForeignKey(School, models.DO_NOTHING)
    name = models.CharField(max_length=100)
    vehicle = models.OneToOneField('Vehicle', models.DO_NOTHING, blank=True, null=True)
    driver = models.OneToOneField(Driver, models.DO_NOTHING, blank=True, null=True)
    status = models.CharField(max_length=20)
    created_at = UtcDateTimeField(blank=True, null=True)
    updated_at = UtcDateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'transport_routes'
        unique_together = (('school', 'name'),)

class TransportStop(models.Model):
    id = models.BigAutoField(primary_key=True)
    school = models.ForeignKey(School, models.DO_NOTHING)
    route = models.ForeignKey(TransportRoute, models.DO_NOTHING)
    name = models.CharField(max_length=100)
    sequence_number = models.SmallIntegerField()
    pickup_time = models.TimeField(blank=True, null=True)
    drop_time = models.TimeField(blank=True, null=True)
    created_at = UtcDateTimeField(blank=True, null=True)
    updated_at = UtcDateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'transport_stops'
        unique_together = (('route', 'sequence_number'), ('route', 'name'),)

class TransportTrip(models.Model):
    id = models.BigAutoField(primary_key=True)
    school = models.ForeignKey(School, models.DO_NOTHING)
    route = models.ForeignKey(TransportRoute, models.DO_NOTHING)
    vehicle = models.ForeignKey('Vehicle', models.DO_NOTHING)
    driver = models.ForeignKey(Driver, models.DO_NOTHING)
    trip_date = models.DateField()
    direction = models.CharField(max_length=10)
    status = models.CharField(max_length=20)
    current_stop = models.ForeignKey(TransportStop, models.DO_NOTHING, blank=True, null=True)
    started_by = models.ForeignKey('User', models.DO_NOTHING, db_column='started_by')
    started_at = UtcDateTimeField()
    ended_at = UtcDateTimeField(blank=True, null=True)
    created_at = UtcDateTimeField(blank=True, null=True)
    updated_at = UtcDateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'transport_trips'

class TransportTripEvent(models.Model):
    id = models.BigAutoField(primary_key=True)
    school = models.ForeignKey(School, models.DO_NOTHING)
    trip = models.ForeignKey('TransportTrip', models.DO_NOTHING)
    type = models.CharField(max_length=20)
    stop = models.ForeignKey(TransportStop, models.DO_NOTHING, blank=True, null=True)
    stop_name = models.CharField(max_length=100, blank=True, null=True)
    student = models.ForeignKey(Student, models.DO_NOTHING, blank=True, null=True)
    student_name = models.CharField(max_length=150, blank=True, null=True)
    recorded_by = models.ForeignKey('User', models.DO_NOTHING, db_column='recorded_by')
    recorded_at = UtcDateTimeField()
    note = models.CharField(max_length=255, blank=True, null=True)
    created_at = UtcDateTimeField(blank=True, null=True)
    updated_at = UtcDateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'transport_trip_events'

class TransportTripRider(models.Model):
    id = models.BigAutoField(primary_key=True)
    trip = models.ForeignKey('TransportTrip', models.DO_NOTHING)
    student = models.ForeignKey(Student, models.DO_NOTHING)
    stop = models.ForeignKey(TransportStop, models.DO_NOTHING, blank=True, null=True)
    stop_name = models.CharField(max_length=100)
    stop_sequence_number = models.SmallIntegerField()
    status = models.CharField(max_length=20)
    boarded_at = UtcDateTimeField(blank=True, null=True)
    dropped_at = UtcDateTimeField(blank=True, null=True)
    created_at = UtcDateTimeField(blank=True, null=True)
    updated_at = UtcDateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'transport_trip_riders'
        unique_together = (('trip', 'student'),)

class User(models.Model):
    id = models.BigAutoField(primary_key=True)
    email = models.CharField(unique=True, max_length=255)
    email_verified_at = UtcDateTimeField(blank=True, null=True)
    password = models.CharField(max_length=255)
    remember_token = models.CharField(max_length=100, blank=True, null=True)
    created_at = UtcDateTimeField(blank=True, null=True)
    updated_at = UtcDateTimeField(blank=True, null=True)
    first_name = models.CharField(max_length=255)
    last_name = models.CharField(max_length=255)
    mobile = models.CharField(max_length=255, blank=True, null=True)
    role = models.CharField(max_length=255)
    status = models.CharField(max_length=255)
    school = models.ForeignKey(School, models.DO_NOTHING, blank=True, null=True)
    is_sub_admin = models.BooleanField()
    must_change_password = models.BooleanField()

    class Meta:
        managed = False
        db_table = 'users'

    # -- behaviour, ported from the Eloquent User model --------------------
    #
    # Kept on the model for the reason Eloquent keeps it there: every caller
    # that has a User has these, and a helper module would let one place
    # answer "is this account active?" differently from another.

    @property
    def name(self) -> str:
        return f"{self.first_name} {self.last_name}".strip()

    def is_active(self) -> bool:
        return self.status == UserStatus.ACTIVE

    @property
    def is_authenticated(self) -> bool:
        """What DRF's permission classes ask of request.user.

        Always True, and that is not a shortcut: an instance of this model
        only ever reaches a view because authentication.py produced it from a
        valid token. An unauthenticated request carries None instead - see
        UNAUTHENTICATED_USER in the REST_FRAMEWORK settings.
        """
        return True

    @property
    def is_anonymous(self) -> bool:
        return False

class Vehicle(models.Model):
    id = models.BigAutoField(primary_key=True)
    school = models.ForeignKey(School, models.DO_NOTHING)
    name = models.CharField(max_length=50)
    registration_number = models.CharField(max_length=30)
    capacity = models.SmallIntegerField()
    status = models.CharField(max_length=20)
    created_at = UtcDateTimeField(blank=True, null=True)
    updated_at = UtcDateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'vehicles'
        unique_together = (('school', 'registration_number'),)
