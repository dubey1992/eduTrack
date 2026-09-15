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
            // A school user imports into their own school and cannot say
            // otherwise. Only a Super Admin, who belongs to none, names one.
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
