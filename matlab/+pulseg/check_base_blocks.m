function [pulseg_ir, report] = check_base_blocks(pulseg_ir, varargin)
% CHECK_BASE_BLOCKS Check and optionally hydrate PulSeg BaseBlock.block structs.
%
% Syntax:
%   pulseg.check_base_blocks(pulseg_ir)
%   [pulseg_ir, report] = pulseg.check_base_blocks(pulseg_ir)
%   [pulseg_ir, report] = pulseg.check_base_blocks(pulseg_ir, 'hydrate', true)
%
% Description:
%   CHECK_BASE_BLOCKS verifies that every explicit PulSeg BaseBlock.block is a
%   normalized Pulseq-like block.
%
%   It is a wrapper around pulseg.check_pulseq_block and is intended to be used
%   by:
%
%       pulseg.validate_ir(...), with 'hydrate', false
%       pulseg.write_seq(...),  with 'hydrate', true
%
% Options:
%   hydrate
%       false by default. If true, hydrate each BaseBlock.block by adding
%       harmless missing Pulseq event fields required by MATLAB Pulseq writer.
%
%   require_normalized
%       true by default. If true, RF and gradient events are required to be
%       normalized according to PulSeg normalization rules.
%
%   error_on_fail
%       true by default. If true, throw an error if any base block fails.
%
%   forbid_explicit_delay_blocks
%       true by default. If true, explicit base blocks with IDs >= 2 may not
%       be pure delay blocks. Delays should use reserved IDs 0 and 1.
%
%   strip_metadata_extensions
%       false by default. If true and hydrate is true, label/trig/rotation
%       fields are removed from BaseBlock.block.
%
%   check_block_duration_consistency
%       false by default. Passed through to pulseg.check_pulseq_block.
%
%   duration_tolerance
%       1e-9 by default. Tolerance for optional duration consistency check.
%
% Outputs:
%   pulseg_ir
%       Original or hydrated PulSeg IR.
%
%   report
%       Struct with fields:
%           ok
%           errors
%           warnings
%           repairs

import pulseg.*

arg.hydrate = false;
arg.require_normalized = true;
arg.error_on_fail = true;
arg.forbid_explicit_delay_blocks = true;
arg.strip_metadata_extensions = false;
arg.check_block_duration_consistency = false;
arg.duration_tolerance = 1e-9;

arg = vararg_pair(arg, varargin);

report = empty_report();

%% Basic IR/base_blocks structure

if ~isstruct(pulseg_ir)
    report = add_error(report, 'Input must be a PulSeg IR struct.');
    finish_or_throw(report, arg.error_on_fail);
    return;
end

if ~isfield(pulseg_ir, 'base_blocks') || isempty(pulseg_ir.base_blocks)
    report = add_error(report, 'pulseg_ir.base_blocks is missing or empty.');
    finish_or_throw(report, arg.error_on_fail);
    return;
end

if ~isstruct(pulseg_ir.base_blocks)
    report = add_error(report, 'pulseg_ir.base_blocks must be a struct array.');
    finish_or_throw(report, arg.error_on_fail);
    return;
end

%% Check each explicit base block

base_ids = nan(1, numel(pulseg_ir.base_blocks));

for p = 1:numel(pulseg_ir.base_blocks)

    bb_name = sprintf('base_blocks(%d)', p);

    %% Required BaseBlock fields

    if ~isfield(pulseg_ir.base_blocks(p), 'id')
        report = add_error(report, sprintf('%s is missing required field "id".', bb_name));
        continue;
    end

    if ~isfield(pulseg_ir.base_blocks(p), 'block')
        report = add_error(report, sprintf('%s is missing required field "block".', bb_name));
        continue;
    end

    %% BaseBlock.id

    id = pulseg_ir.base_blocks(p).id;

    if ~(isnumeric(id) && isscalar(id) && isfinite(id) && id == floor(id))
        report = add_error(report, sprintf('%s.id must be an integer.', bb_name));
        continue;
    end

    if id < 2
        report = add_error(report, sprintf( ...
            '%s.id must be >= 2. IDs 0 and 1 are reserved implicit delay blocks.', ...
            bb_name));
        continue;
    end

    base_ids(p) = id;

    %% BaseBlock.block

    block_name = sprintf('%s.block', bb_name);

    try
        [block_out, block_report] = pulseg.check_pulseq_block( ...
            pulseg_ir.base_blocks(p).block, ...
            block_name, ...
            'hydrate', arg.hydrate, ...
            'require_normalized', arg.require_normalized, ...
            'forbid_explicit_delay_blocks', arg.forbid_explicit_delay_blocks, ...
            'strip_metadata_extensions', arg.strip_metadata_extensions, ...
            'check_block_duration_consistency', arg.check_block_duration_consistency, ...
            'duration_tolerance', arg.duration_tolerance, ...
            'error_on_fail', false);

        report = merge_reports(report, block_report);

        if arg.hydrate
            pulseg_ir.base_blocks(p).block = block_out;
        end

    catch ME
        report = add_error(report, sprintf('%s failed Pulseq block check: %s', ...
            block_name, ME.message));
    end
end

%% Check base block ID uniqueness, if all IDs were parseable

valid_id_mask = ~isnan(base_ids);

if any(valid_id_mask)
    parsed_ids = base_ids(valid_id_mask);

    if numel(unique(parsed_ids)) ~= numel(parsed_ids)
        report = add_error(report, 'Base block IDs must be unique.');
    end
end

finish_or_throw(report, arg.error_on_fail);

return


%% ------------------------------------------------------------------------
%  Report helpers
%  ------------------------------------------------------------------------

function report = empty_report()

report.ok = true;
report.errors = {};
report.warnings = {};
report.repairs = {};

return


function report = add_error(report, msg)

report.ok = false;
report.errors{end+1} = msg;

return


function report = add_warning(report, msg)

report.warnings{end+1} = msg;

return


function report = add_repair(report, msg)

report.repairs{end+1} = msg;

return


function report = merge_reports(report, other)

if ~isstruct(other)
    report = add_error(report, 'Internal error: attempted to merge a non-struct report.');
    return;
end

if isfield(other, 'ok') && ~other.ok
    report.ok = false;
end

if isfield(other, 'errors') && ~isempty(other.errors)
    report.errors = [report.errors other.errors];
end

if isfield(other, 'warnings') && ~isempty(other.warnings)
    report.warnings = [report.warnings other.warnings];
end

if isfield(other, 'repairs') && ~isempty(other.repairs)
    report.repairs = [report.repairs other.repairs];
end

return


function finish_or_throw(report, error_on_fail)

if error_on_fail && ~report.ok
    msg = sprintf('PulSeg base block validation failed with %d error(s):\n', ...
        numel(report.errors));

    for ii = 1:numel(report.errors)
        msg = sprintf('%s  %d. %s\n', msg, ii, report.errors{ii});
    end

    error('%s', msg);
end

return
