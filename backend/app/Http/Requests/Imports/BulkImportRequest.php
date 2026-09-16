<?php

namespace App\Http\Requests\Imports;

use App\Http\Requests\Concerns\ScopesSchool;
use Illuminate\Foundation\Http\FormRequest;

class BulkImportRequest extends FormRequest
{
    use ScopesSchool;

    /**
     * Who may import what is the same question as who may add one by hand,
     * and it needs the type from the route - so the controller asks the
     * policy rather than this form.
     */
    public function authorize(): bool
    {
        return true;
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            // Two megabytes is several thousand rows of text, well past the
            // 2,000-row ceiling the import itself enforces.
            'file' => ['required', 'file', 'mimes:csv,txt', 'max:2048'],
            // An actor with one school imports into it and cannot say
            // otherwise. Anybody reaching several - a Super Admin, or an
            // admin of a school in a group - names the one they mean. A
            // spreadsheet is filed into a branch, never into a group.
            'school_id' => $this->schoolIdRules(),
        ];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'file.mimes' => 'Upload a CSV file. In Excel, choose File - Save As - CSV.',
        ];
    }
}
