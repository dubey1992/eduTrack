---
kind: help
slug: import-students-from-a-spreadsheet
title: Import students from a spreadsheet
topic: getting-started
summary: How to add a whole roll of students at once by filling in the School365ai template and uploading it as a CSV file, and what to do when some rows need fixing.
---
This article shows you how to add many students in one go by uploading a spreadsheet, instead of typing each one into the **Add Student** form.

## Who can do this

A School Admin can import students on the web. A Super Admin can too, after choosing the school in the list's filter.

## Before you start

Your classes and sections must already exist in the current academic year, because each row names its class and section. If they are not there yet, see [Set up your school](/help/set-up-your-school).

## Steps

1. Open **Students** in the sidebar and choose **Bulk Upload**.
2. Choose **Download template**. You get a CSV file with the column headings and one example row.
3. Open the file in your spreadsheet program and fill in one row per student. The columns are admission_number, first_name, last_name, class, section, roll_number, guardian_name, guardian_mobile and address.
4. Delete the example row, then save the file as CSV. Most spreadsheet programs have this under Save As.
5. Back in the dialog, choose **Choose file** and pick your saved file.
6. Choose **Check file**. School365ai reads the file and shows you the first rows and the total, so you can confirm it is the right file. If it is not, choose **Choose another file**.
7. Choose the Import button, which shows how many rows will be added, for example Import 120. When it finishes you see a short summary. Choose **Done**.

## If some rows have problems

Nothing is imported unless every row is valid. If any row has a problem, you see every bad row at once, with its row number and what is wrong, such as a class that does not exist or an admission number that is already taken. Fix those rows in your spreadsheet, save it again and upload it again.

## Good to know

- Write class and section names exactly as they appear in **Classes & Sections**. Capital letters and extra spaces do not matter.
- Admission numbers must be unique in your school. The import refuses a file that repeats one, or that uses one a student already has.
- Each file can hold up to 2,000 rows and be up to 2 MB. Only CSV files are accepted, not .xlsx.
- Add the guardian's mobile number with the country code, as in the example row. That number is where absence alerts go, if your school sends them. See [Send absence alerts to guardians](/help/send-absence-alerts-to-guardians).
