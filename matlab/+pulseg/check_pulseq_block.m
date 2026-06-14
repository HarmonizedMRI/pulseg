function [b, report] = check_pulseq_block(b, block_name, varargin)
% CHECK_PULSEQ_BLOCK Check and optionally hydrate a PulSeg Pulseq-like block.
%
% Syntax:
%   pulseg.check_pulseq_block(b)
%   pulseg.check_pulseq_block(b, block_name)
%   [b, report] = pulseg.check_pulseq_block(b, block_name, 'hydrate', true)
%
% Description:
%   Checks that a PulSeg BaseBlock.block is a normalized Pulseq-like block.
%
%   A PulSeg Pulseq-like block is expected to be a scalar struct with:
%
%       blockDuration
%
%   and zero or more event fields:
%
%       rf, gx, gy, gz, adc
%
%   In hydrate mode, harmless missing Pulseq writer fields are added, e.g.:
%
%       rf.type = 'rf'
%       gx.type = 'grad' or 'trap'
%       gx.channel = 'x'
%       adc.type = 'adc'
%       adc.phaseModulation = []
%
% Options:
%   hydrate
%       false by default. If true, add harmless missing fields.
%
%   require_normalized
%       true by default. If true, verify RF and gradient waveforms/amplitudes
%       are normalized according to the PulSeg 2.0-alpha convention.
%
%   error_on_fail
%       true by default. If true, throw an error if validation fails.
%
%   forbid_explicit_delay_blocks
%       true by default. If true, a block with no rf/gx/gy/gz/adc events is
%       considered invalid as an explicit BaseBlock.block. PulSeg delay
%       blocks should use reserved base block IDs 0 and 1.
%
%   strip_metadata_extensions
%       false by default. If true and hydrate is true, remove label/trig/
%       rotation fields from the block. These are not considered waveform
%       shape fields.
%
%   check_block_duration_consistency
%       false by default. If true, compare b.blockDuration against
%       mr.calcDuration(b) after optional hydration.
%
% Outputs:
%   b
%       Original or hydrated block.
%
%   report
%       Struct with fields:
%           ok
%           errors
%           warnings
%           repairs

import pulseg.*

if nargin < 2 || isempty(block_name)
    block_name = 'PulseqBlock';
end

arg.hydrate = false;
arg.require_normalized = true;
arg.error_on_fail = true;
arg.forbid_explicit_delay_blocks = true;
arg.strip_metadata_extensions = false;
arg.check_block_duration_consistency = false;
arg.duration_tolerance = 1e-9;

arg = vararg_pair(arg, varargin);

report = empty_report();

%% Basic block structure

if ~isstruct(b) || ~isscalar(b)
    report = add_error(report, sprintf('%s must be a scalar struct.', block_name));
    finish_or_throw(report, arg.error_on_fail);
    return;
end

%% blockDuration

block_duration_missing = false;

if ~isfield(b, 'blockDuration') || isempty(b.blockDuration)
    block_duration_missing = true;

    if ~arg.hydrate
        report = add_error(report, sprintf('%s.blockDuration is missing.', block_name));
    end
else
    if ~(isnumeric(b.blockDuration) && isscalar(b.blockDuration) && ...
            isfinite(b.blockDuration) && b.blockDuration >= 0)
        report = add_error(report, sprintf( ...
            '%s.blockDuration must be a finite non-negative scalar.', block_name));
    end
end

%% Metadata/extensions

metadata_fields = {'label', 'trig', 'rotation'};

for ii = 1:numel(metadata_fields)
    f = metadata_fields{ii};

    if isfield(b, f) && ~isempty(b.(f))
        if arg.hydrate && arg.strip_metadata_extensions
            b = rmfield(b, f);
            report = add_repair(report, sprintf( ...
                '%s.%s was stripped from base block.', block_name, f));
        else
            report = add_warning(report, sprintf( ...
                ['%s.%s is present. BaseBlock.block should ideally contain ', ...
                 'waveform/timing shape only.'], ...
                block_name, f));
        end
    end
end

%% Event presence

has_rf  = has_event(b, 'rf');
has_gx  = has_event(b, 'gx');
has_gy  = has_event(b, 'gy');
has_gz  = has_event(b, 'gz');
has_adc = has_event(b, 'adc');

if arg.forbid_explicit_delay_blocks && ~(has_rf || has_gx || has_gy || has_gz || has_adc)
    report = add_error(report, sprintf( ...
        ['%s is a pure-delay block. Explicit PulSeg BaseBlock.block entries ', ...
         'should contain at least one RF, gradient, or ADC event. Use reserved ', ...
         'base block IDs 0 or 1 for delays.'], ...
        block_name));
end

%% RF

if has_rf
    [b.rf, r] = check_rf_event(b.rf, sprintf('%s.rf', block_name), arg);
    report = merge_reports(report, r);
end

%% Gradients

if has_gx
    [b.gx, r] = check_gradient_event(b.gx, 'x', sprintf('%s.gx', block_name), arg);
    report = merge_reports(report, r);
end

if has_gy
    [b.gy, r] = check_gradient_event(b.gy, 'y', sprintf('%s.gy', block_name), arg);
    report = merge_reports(report, r);
end

if has_gz
    [b.gz, r] = check_gradient_event(b.gz, 'z', sprintf('%s.gz', block_name), arg);
    report = merge_reports(report, r);
end

%% ADC

if has_adc
    [b.adc, r] = check_adc_event(b.adc, sprintf('%s.adc', block_name), arg);
    report = merge_reports(report, r);
end

%% Hydrate missing blockDuration, if requested

if block_duration_missing && arg.hydrate
    try
        b.blockDuration = mr.calcDuration(b);
        report = add_repair(report, sprintf( ...
            '%s.blockDuration was inferred using mr.calcDuration.', block_name));
    catch ME
        report = add_error(report, sprintf( ...
            '%s.blockDuration is missing and could not be inferred using mr.calcDuration: %s', ...
            block_name, ME.message));
    end
end

%% Optional duration consistency check

if arg.check_block_duration_consistency && isfield(b, 'blockDuration') && ~isempty(b.blockDuration)
    try
        duration_recomputed = mr.calcDuration(b);

        if abs(duration_recomputed - b.blockDuration) > arg.duration_tolerance
            report = add_error(report, sprintf( ...
                ['%s.blockDuration is inconsistent with mr.calcDuration. ', ...
                 'blockDuration = %.15g, mr.calcDuration = %.15g, diff = %.15g.'], ...
                block_name, b.blockDuration, duration_recomputed, ...
                duration_recomputed - b.blockDuration));
        end
    catch ME
        report = add_warning(report, sprintf( ...
            '%s duration consistency check failed because mr.calcDuration errored: %s', ...
            block_name, ME.message));
    end
end

finish_or_throw(report, arg.error_on_fail);

return


%% ------------------------------------------------------------------------
%  RF event checker
%  ------------------------------------------------------------------------

function [rf, report] = check_rf_event(rf, name, arg)

report = empty_report();

if ~isstruct(rf) || ~isscalar(rf)
    report = add_error(report, sprintf('%s must be a scalar struct.', name));
    return;
end

required = {'signal', 't', 'center'};

for ii = 1:numel(required)
    f = required{ii};

    if ~isfield(rf, f) || isempty(rf.(f))
        report = add_error(report, sprintf('%s is missing required field "%s".', name, f));
    end
end

%% signal

if isfield(rf, 'signal') && ~isempty(rf.signal)
    if ~isnumeric(rf.signal) || any(~isfinite(rf.signal(:)))
        report = add_error(report, sprintf('%s.signal must be finite numeric.', name));
    elseif arg.require_normalized
        peak = max(abs(rf.signal(:)));
        tol = 1e-9;

        if peak > 1 + tol
            report = add_error(report, sprintf( ...
                '%s.signal exceeds normalized amplitude. max(abs(signal)) = %.15g.', ...
                name, peak));
        elseif peak > tol && abs(peak - 1) > tol
            report = add_error(report, sprintf( ...
                '%s.signal is nonzero but not normalized. max(abs(signal)) = %.15g.', ...
                name, peak));
        end
    end
end

%% t

if isfield(rf, 't') && ~isempty(rf.t)
    if ~isnumeric(rf.t) || ~isvector(rf.t) || ...
            any(~isfinite(rf.t(:))) || any(rf.t(:) < 0)
        report = add_error(report, sprintf( ...
            '%s.t must be a finite non-negative numeric vector.', name));
    end
end

%% center

if isfield(rf, 'center') && ~isempty(rf.center)
    if ~(isnumeric(rf.center) && isscalar(rf.center) && ...
            isfinite(rf.center) && rf.center >= 0)
        report = add_error(report, sprintf( ...
            '%s.center must be a finite non-negative scalar.', name));
    end
end

%% RF time/signal compatibility

if isfield(rf, 'signal') && ~isempty(rf.signal) && ...
        isfield(rf, 't') && ~isempty(rf.t)

    n_t = numel(rf.t);
    sig_size = size(rf.signal);

    if ~(numel(rf.signal) == n_t || any(sig_size == n_t))
        report = add_error(report, sprintf( ...
            ['%s.t length is not compatible with %s.signal size. ', ...
             'Expected numel(t) to match numel(signal) or one signal dimension.'], ...
            name, name));
    end
end

%% Hydratable/default fields

if arg.hydrate
    rf.type = 'rf';

    [rf, report] = default_scalar_field(rf, report, name, 'delay', 0);
    [rf, report] = default_scalar_field(rf, report, name, 'phaseOffset', 0);
    [rf, report] = default_scalar_field(rf, report, name, 'freqOffset', 0);
    [rf, report] = default_scalar_field(rf, report, name, 'deadTime', 0);
    [rf, report] = default_scalar_field(rf, report, name, 'ringdownTime', 0);
else
    if isfield(rf, 'type') && ~isempty(rf.type)
        if ~(ischar(rf.type) || isstring(rf.type))
            report = add_error(report, sprintf('%s.type must be a string if present.', name));
        end
    end

    report = check_optional_scalar(rf, report, name, 'delay', true);
    report = check_optional_scalar(rf, report, name, 'phaseOffset', false);
    report = check_optional_scalar(rf, report, name, 'freqOffset', false);
    report = check_optional_scalar(rf, report, name, 'deadTime', true);
    report = check_optional_scalar(rf, report, name, 'ringdownTime', true);
end

%% Optional textual RF use

if isfield(rf, 'use') && ~isempty(rf.use)
    if ~(ischar(rf.use) || isstring(rf.use))
        report = add_error(report, sprintf('%s.use must be a string if present.', name));
    end
end

return


%% ------------------------------------------------------------------------
%  Gradient event checker
%  ------------------------------------------------------------------------

function [g, report] = check_gradient_event(g, channel, name, arg)

report = empty_report();

if ~isstruct(g) || ~isscalar(g)
    report = add_error(report, sprintf('%s must be a scalar struct.', name));
    return;
end

has_waveform  = isfield(g, 'waveform')  && ~isempty(g.waveform);
has_amplitude = isfield(g, 'amplitude') && ~isempty(g.amplitude);

if ~has_waveform && ~has_amplitude
    report = add_error(report, sprintf( ...
        '%s must contain either waveform or amplitude.', name));
    return;
end

%% Channel

if arg.hydrate
    g.channel = char(channel);
else
    if isfield(g, 'channel') && ~isempty(g.channel)
        if ~(ischar(g.channel) || isstring(g.channel))
            report = add_error(report, sprintf('%s.channel must be a string if present.', name));
        elseif ~strcmp(char(g.channel), char(channel))
            report = add_warning(report, sprintf( ...
                '%s.channel is "%s", but block field implies channel "%s".', ...
                name, char(g.channel), char(channel)));
        end
    end
end

%% Type, if present

if ~arg.hydrate && isfield(g, 'type') && ~isempty(g.type)
    if ~(ischar(g.type) || isstring(g.type))
        report = add_error(report, sprintf('%s.type must be a string if present.', name));
    end
end

%% Prefer waveform representation if both waveform and amplitude are present.

if has_waveform && has_amplitude
    report = add_warning(report, sprintf( ...
        ['%s contains both waveform and amplitude. Treating it as an arbitrary ', ...
         'gradient because waveform is present.'], name));
end

%% Arbitrary/sampled gradient

if has_waveform

    if arg.hydrate
        g.type = 'grad';
    end

    if ~isnumeric(g.waveform) || ~isvector(g.waveform) || any(~isfinite(g.waveform(:)))
        report = add_error(report, sprintf('%s.waveform must be a finite numeric vector.', name));
    end

    if ~isfield(g, 'tt') || isempty(g.tt)
        report = add_error(report, sprintf('%s.tt is required for arbitrary gradients.', name));
    else
        if ~isnumeric(g.tt) || ~isvector(g.tt) || ...
                any(~isfinite(g.tt(:))) || any(g.tt(:) < 0)
            report = add_error(report, sprintf( ...
                '%s.tt must be a finite non-negative numeric vector.', name));
        elseif isfield(g, 'waveform') && ~isempty(g.waveform) && ...
                numel(g.tt) ~= numel(g.waveform)
            report = add_error(report, sprintf( ...
                '%s.tt and %s.waveform must have the same number of samples. Found %d and %d.', ...
                name, name, numel(g.tt), numel(g.waveform)));
        elseif any(diff(g.tt(:)) < 0)
            report = add_error(report, sprintf('%s.tt must be monotonically nondecreasing.', name));
        end
    end

    if arg.hydrate
        [g, report] = default_scalar_field(g, report, name, 'delay', 0);

        if ~isfield(g, 'first') || isempty(g.first)
            if isfield(g, 'waveform') && ~isempty(g.waveform)
                g.first = g.waveform(1);
                report = add_repair(report, sprintf( ...
                    '%s.first was set from waveform(1).', name));
            end
        end

        if ~isfield(g, 'last') || isempty(g.last)
            if isfield(g, 'waveform') && ~isempty(g.waveform)
                g.last = g.waveform(end);
                report = add_repair(report, sprintf( ...
                    '%s.last was set from waveform(end).', name));
            end
        end

        % Avoid stale arbitrary-gradient duration fields. Pulseq can infer
        % sampled-gradient duration from timing/waveform fields.
        if isfield(g, 'duration')
            g = rmfield(g, 'duration');
            report = add_repair(report, sprintf( ...
                '%s.duration was removed for arbitrary gradient.', name));
        end
    else
        if ~isfield(g, 'first') || isempty(g.first)
            report = add_error(report, sprintf( ...
                '%s.first is required for arbitrary gradients.', name));
        else
            report = check_scalar_field_if_present(g, report, name, 'first', false);
        end

        if ~isfield(g, 'last') || isempty(g.last)
            report = add_error(report, sprintf( ...
                '%s.last is required for arbitrary gradients.', name));
        else
            report = check_scalar_field_if_present(g, report, name, 'last', false);
        end

        report = check_optional_scalar(g, report, name, 'delay', true);
        report = check_optional_scalar(g, report, name, 'duration', true);
    end

    if arg.require_normalized && isnumeric(g.waveform) && ~isempty(g.waveform)
        peak = max(abs(g.waveform(:)));
        tol = 1e-9;

        if peak > 1 + tol
            report = add_error(report, sprintf( ...
                '%s.waveform exceeds normalized amplitude. max(abs(waveform)) = %.15g.', ...
                name, peak));
        elseif peak > tol && abs(peak - 1) > tol
            report = add_error(report, sprintf( ...
                '%s.waveform is nonzero but not normalized. max(abs(waveform)) = %.15g.', ...
                name, peak));
        end
    end

    return;
end

%% Trapezoid/scalar gradient

if has_amplitude

    if arg.hydrate
        g.type = 'trap';
    end

    if ~(isnumeric(g.amplitude) && isscalar(g.amplitude) && isfinite(g.amplitude))
        report = add_error(report, sprintf('%s.amplitude must be a finite scalar.', name));
    end

    required_trap = {'riseTime', 'flatTime', 'fallTime'};

    for ii = 1:numel(required_trap)
        f = required_trap{ii};

        if ~isfield(g, f) || isempty(g.(f))
            report = add_error(report, sprintf('%s is missing required field "%s".', name, f));
        elseif ~(isnumeric(g.(f)) && isscalar(g.(f)) && isfinite(g.(f)) && g.(f) >= 0)
            report = add_error(report, sprintf('%s.%s must be finite and non-negative.', name, f));
        end
    end

    if arg.hydrate
        [g, report] = default_scalar_field(g, report, name, 'delay', 0);

        if all(isfield(g, required_trap)) && ...
                is_valid_nonnegative_scalar(g.riseTime) && ...
                is_valid_nonnegative_scalar(g.flatTime) && ...
                is_valid_nonnegative_scalar(g.fallTime)

            g.duration = g.riseTime + g.flatTime + g.fallTime;
            report = add_repair(report, sprintf( ...
                '%s.duration was set from riseTime + flatTime + fallTime.', name));
        end
    else
        report = check_optional_scalar(g, report, name, 'delay', true);
        report = check_optional_scalar(g, report, name, 'duration', true);
    end

    report = check_optional_scalar(g, report, name, 'area', false);
    report = check_optional_scalar(g, report, name, 'flatArea', false);

    if arg.require_normalized && isnumeric(g.amplitude) && isscalar(g.amplitude)
        amp = g.amplitude;
        tol = 1e-9;

        if abs(amp) > 1 + tol
            report = add_error(report, sprintf( ...
                '%s.amplitude exceeds normalized magnitude. amplitude = %.15g.', ...
                name, amp));
        elseif abs(amp) > tol && abs(abs(amp) - 1) > tol
            report = add_error(report, sprintf( ...
                '%s.amplitude is nonzero but not normalized. amplitude = %.15g.', ...
                name, amp));
        end
    end
end

return


%% ------------------------------------------------------------------------
%  ADC event checker
%  ------------------------------------------------------------------------

function [adc, report] = check_adc_event(adc, name, arg)

report = empty_report();

if ~isstruct(adc) || ~isscalar(adc)
    report = add_error(report, sprintf('%s must be a scalar struct.', name));
    return;
end

required = {'numSamples', 'dwell', 'delay'};

for ii = 1:numel(required)
    f = required{ii};

    if ~isfield(adc, f) || isempty(adc.(f))
        report = add_error(report, sprintf('%s is missing required field "%s".', name, f));
    end
end

if isfield(adc, 'numSamples') && ~isempty(adc.numSamples)
    if ~(isnumeric(adc.numSamples) && isscalar(adc.numSamples) && ...
            isfinite(adc.numSamples) && adc.numSamples == floor(adc.numSamples) && ...
            adc.numSamples > 0)
        report = add_error(report, sprintf('%s.numSamples must be a positive integer.', name));
    end
end

if isfield(adc, 'dwell') && ~isempty(adc.dwell)
    if ~(isnumeric(adc.dwell) && isscalar(adc.dwell) && ...
            isfinite(adc.dwell) && adc.dwell > 0)
        report = add_error(report, sprintf('%s.dwell must be positive.', name));
    end
end

if isfield(adc, 'delay') && ~isempty(adc.delay)
    if ~(isnumeric(adc.delay) && isscalar(adc.delay) && ...
            isfinite(adc.delay) && adc.delay >= 0)
        report = add_error(report, sprintf('%s.delay must be non-negative.', name));
    end
end

if arg.hydrate
    adc.type = 'adc';

    [adc, report] = default_scalar_field(adc, report, name, 'phaseOffset', 0);
    [adc, report] = default_scalar_field(adc, report, name, 'freqOffset', 0);

    if ~isfield(adc, 'phaseModulation')
        adc.phaseModulation = [];
        report = add_repair(report, sprintf( ...
            '%s.phaseModulation was set to [].', name));
    end
else
    if isfield(adc, 'type') && ~isempty(adc.type)
        if ~(ischar(adc.type) || isstring(adc.type))
            report = add_error(report, sprintf('%s.type must be a string if present.', name));
        end
    end

    report = check_optional_scalar(adc, report, name, 'phaseOffset', false);
    report = check_optional_scalar(adc, report, name, 'freqOffset', false);
end

return


%% ------------------------------------------------------------------------
%  Generic helpers
%  ------------------------------------------------------------------------

function tf = has_event(b, fieldname)

tf = isstruct(b) && isfield(b, fieldname) && ~isempty(b.(fieldname));

return


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

if ~other.ok
    report.ok = false;
end

report.errors = [report.errors other.errors];
report.warnings = [report.warnings other.warnings];
report.repairs = [report.repairs other.repairs];

return


function [s, report] = default_scalar_field(s, report, name, fieldname, default)

if ~isfield(s, fieldname) || isempty(s.(fieldname))
    s.(fieldname) = default;
    report = add_repair(report, sprintf( ...
        '%s.%s was set to %.15g.', name, fieldname, default));
else
    report = check_scalar_field_if_present(s, report, name, fieldname, false);
end

return


function report = check_optional_scalar(s, report, name, fieldname, require_nonnegative)

if ~isfield(s, fieldname) || isempty(s.(fieldname))
    return;
end

val = s.(fieldname);

if ~(isnumeric(val) && isscalar(val) && isfinite(val))
    report = add_error(report, sprintf( ...
        '%s.%s must be a finite scalar if present.', name, fieldname));
    return;
end

if require_nonnegative && val < 0
    report = add_error(report, sprintf( ...
        '%s.%s must be non-negative if present.', name, fieldname));
end

return


function report = check_scalar_field_if_present(s, report, name, fieldname, require_nonnegative)

if ~isfield(s, fieldname) || isempty(s.(fieldname))
    return;
end

val = s.(fieldname);

if ~(isnumeric(val) && isscalar(val) && isfinite(val))
    report = add_error(report, sprintf( ...
        '%s.%s must be a finite scalar.', name, fieldname));
    return;
end

if require_nonnegative && val < 0
    report = add_error(report, sprintf( ...
        '%s.%s must be non-negative.', name, fieldname));
end

return


function tf = is_valid_nonnegative_scalar(x)

tf = isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0;

return


function finish_or_throw(report, error_on_fail)

if error_on_fail && ~report.ok
    msg = sprintf('PulSeg Pulseq block validation failed with %d error(s):\n', ...
        numel(report.errors));

    for ii = 1:numel(report.errors)
        msg = sprintf('%s  %d. %s\n', msg, ii, report.errors{ii});
    end

    error('%s', msg);
end

return
