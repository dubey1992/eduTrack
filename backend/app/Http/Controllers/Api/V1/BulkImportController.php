<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Imports\BulkImportRequest;
use App\Services\Imports\BulkImportService;
use App\Services\Imports\ImportRegistry;
use App\Services\Imports\RowImporter;
use App\Support\Reports\CsvResponse;
use App\Support\SchoolScope;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Bulk upload: download a template, fill it in, send it back.
 *
 * One pair of endpoints covers every kind of record, because the only thing
 * that differs between importing students and importing vehicles is the
 * importer - see App\Services\Imports.
 */
class BulkImportController extends Controller
{
    public function __construct(
        private readonly ImportRegistry $registry,
        private readonly BulkImportService $imports,
    ) {}

    /**
     * The empty spreadsheet, with one example row so nobody has to guess how
     * a date or a phone number should look.
     */
    public function template(Request $request, string $type): StreamedResponse
    {
        $importer = $this->importerFor($request, $type);

        return CsvResponse::make("{$type}-template.csv", $importer->headings(), [$importer->sample()]);
    }

    public function store(BulkImportRequest $request, string $type): JsonResponse
    {
        $importer = $this->importerFor($request, $type);
        $actor = $request->user();

        $schoolId = (int) SchoolScope::for($actor)->writableSchoolId($request->integer('school_id') ?: null);

        // A bad file throws BulkImportFailedException, which the API error
        // renderer turns into a 422 listing every row that needs fixing.
        return response()->json(
            $this->imports->import($importer, $request->file('file'), $schoolId, $actor),
            201,
        );
    }

    /**
     * Resolves the kind of import being asked for, and checks the actor is
     * allowed to create that kind of record at all.
     */
    private function importerFor(Request $request, string $type): RowImporter
    {
        abort_unless($this->registry->has($type), 404, 'There is nothing of that kind to import.');

        Gate::forUser($request->user())->authorize('create', $this->registry->model($type));

        return $this->registry->importer($type);
    }
}
