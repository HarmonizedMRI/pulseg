function seq = write_seq(pulseg_ir, seqfile, varargin)
% WRITE_SEQ Flatten a PulSeg IR struct to a Pulseq sequence and write a .seq file.
%
% Syntax:
%   seq = pulseg.write_seq(pulseg_ir, seqfile)
%   seq = pulseg.write_seq(pulseg_ir, seqfile, 'strict', true)
%
% Inputs
%   pulseg_ir
%       PulSeg 2.0-alpha IR struct.
%
%   seqfile
%       Output Pulseq .seq filename.
%
% Options
%   strict      true/FALSE
%       If true, validate the IR and enforce conservative checks.
%
%   verbose     true/FALSE
%       Print progress information.
%
%   system      []
%       Optional Pulseq system limits object passed to mr.Sequence(system).
%
% Limitations
%   - Non-identity gradient rotation matrices are not yet exported.
%   - physio_trigger is not yet exported.
%   - Segment labels/TRID labels are not yet regenerated.
%
% Output
%   seq
%       Flattened mr.Sequence object.

import pulseg.*

arg.strict = true;
arg.verbose = false;
arg.system = [];
arg = vararg_pair(arg, varargin);

if arg.strict
    pulseg.validate_ir(pulseg_ir);
end

if nargin < 2 || isempty(seqfile)
    error('An output .seq filename must be provided.');
end

if isempty(arg.system)
    seq = mr.Sequence();
else
    seq = mr.Sequence(arg.system);
end

base_ids = [pulseg_ir.base_blocks.id];
vs_ids = [pulseg_ir.virtual_segments.id];

n_instances = numel(pulseg_ir.execution_stream);

if arg.verbose
    fprintf('Flattening PulSeg IR with %d segment instances...\n', n_instances);
end

for k = 1:n_instances

    inst = pulseg_ir.execution_stream(k);

    s = find(vs_ids == inst.virtual_segment_id, 1);
    assert(~isempty(s), ...
        'execution_stream(%d).virtual_segment_id references unknown virtual segment ID %d.', ...
        k, inst.virtual_segment_id);

    vs = pulseg_ir.virtual_segments(s);

    rf_i = 0;
    grad_i = 0;
    adc_i = 0;

    if isfield(inst, 'physio_trigger') && ~isempty(inst.physio_trigger) && inst.physio_trigger ~= 0
        error(['execution_stream(%d).physio_trigger is set, but physio trigger ' ...
               'export is not implemented in pulseg.write_seq yet.'], k);
    end

    for j = 1:numel(vs.base_block_ids)

        base_id = vs.base_block_ids(j);
        requested_duration = inst.block_duration(j);

        if base_id == 0 || base_id == 1
            % Reserved implicit delay blocks.
            delay_event = mr.makeDelay(requested_duration);
            seq.addBlock(delay_event);
            continue;
        end

        p = find(base_ids == base_id, 1);
        assert(~isempty(p), ...
            'Virtual segment %d references unknown base block ID %d.', ...
            vs.id, base_id);

        % Copy normalized base block.
        b = pulseg_ir.base_blocks(p).block;

        % Remove stream-local or source-file metadata/extensions that should
        % not blindly propagate to every emitted block.
        b = strip_non_shape_fields(b);

        has_rf = has_event(b, 'rf');
        has_grad = has_event(b, 'gx') || has_event(b, 'gy') || has_event(b, 'gz');
        has_adc = has_event(b, 'adc');

        if has_rf
            rf_i = rf_i + 1;

            b.rf = scale_rf_event( ...
                b.rf, ...
                inst.rf_amplitude(rf_i), ...
                inst.rf_phase_offset(rf_i), ...
                inst.rf_frequency_offset(rf_i));
        end

        if has_grad
            grad_i = grad_i + 1;

            R = get_rotation_matrix_for_event(inst, grad_i);

            if ~is_identity_matrix(R)
                error(['Non-identity gradient rotation encountered at execution_stream(%d), ' ...
                       'block %d, gradient event %d. Rotation export is not implemented yet.'], ...
                       k, j, grad_i);
            end

            gscale = inst.gradient_amplitude(grad_i, :);

            if has_event(b, 'gx')
                b.gx = scale_gradient_event(b.gx, gscale(1));
            end

            if has_event(b, 'gy')
                b.gy = scale_gradient_event(b.gy, gscale(2));
            end

            if has_event(b, 'gz')
                b.gz = scale_gradient_event(b.gz, gscale(3));
            end
        end

        if has_adc
            adc_i = adc_i + 1;

            b.adc = set_adc_offsets( ...
                b.adc, ...
                inst.adc_phase_offset(adc_i), ...
                inst.adc_frequency_offset(adc_i));
        end

        events = block_to_events(b);

        % Enforce PulSeg block_duration.
        %
        % Important:
        %   Do NOT add mr.makeDelay(requested_duration) into the same block as
        %   RF/gradient/ADC events. Some Pulseq MATLAB versions can accept it during
        %   addBlock(), but then fail the internal duration consistency assertion
        %   during seq.write().
        %
        % Safer MVP behavior:
        %   1. Emit the physical event block.
        %   2. If PulSeg says the block duration is longer than the event block,
        %      emit a separate pure delay block for the trailing dead time.

        base_duration = getfield_default(b, 'blockDuration', 0);
        duration_tol = 1e-9;

        if requested_duration < base_duration - duration_tol
            error(['Requested PulSeg block duration %.12g s is shorter than ' ...
                   'base block duration %.12g s at execution_stream(%d), block %d.'], ...
                   requested_duration, base_duration, k, j);
        end

        % Emit the event block itself.
        seq.addBlock(events{:});

        % Emit trailing delay if the PulSeg block duration is longer.
        extra_delay = requested_duration - base_duration;

        if extra_delay > duration_tol
            seq.addBlock(mr.makeDelay(extra_delay));
        end
    end

    if arg.strict
        assert(rf_i == numel(inst.rf_amplitude), ...
            'execution_stream(%d): consumed %d RF events but instance contains %d RF amplitudes.', ...
            k, rf_i, numel(inst.rf_amplitude));

        assert(grad_i == size(inst.gradient_amplitude, 1), ...
            'execution_stream(%d): consumed %d gradient events but instance contains %d gradient rows.', ...
            k, grad_i, size(inst.gradient_amplitude, 1));

        assert(adc_i == numel(inst.adc_phase_offset), ...
            'execution_stream(%d): consumed %d ADC events but instance contains %d ADC phase offsets.', ...
            k, adc_i, numel(inst.adc_phase_offset));
    end
end

if arg.verbose
    fprintf('Writing Pulseq file: %s\n', seqfile);
end

seq.write(char(seqfile));

if arg.verbose
    fprintf('Done.\n');
end

return


function tf = has_event(b, fieldname)
% HAS_EVENT True if a Pulseq block contains a nonempty event field.

tf = isstruct(b) && isfield(b, fieldname) && ~isempty(b.(fieldname));

return

function b = strip_non_shape_fields(b)
% STRIP_NON_SHAPE_FIELDS Remove metadata/extensions that should not be emitted
% blindly from normalized base blocks.
%
% The normalized BaseBlock should define waveform shape. Stream-level labels,
% triggers, and rotations are dynamic execution metadata and should be rebuilt
% explicitly by the exporter if supported.

remove_fields = {'label', 'trig', 'rotation'};

for ii = 1:numel(remove_fields)
    f = remove_fields{ii};
    if isfield(b, f)
        b = rmfield(b, f);
    end
end

return

function rf = scale_rf_event(rf, amplitude, phase_offset, frequency_offset)
% SCALE_RF_EVENT Restore RF amplitude and offsets from a normalized RF event.

if isfield(rf, 'signal') && ~isempty(rf.signal)
    rf.signal = rf.signal * amplitude;
else
    error('RF event is missing signal field.');
end

% Important: use the instance values as the physical offsets.
% Do not add to any existing base-block offsets, because base blocks should
% represent normalized reusable shapes, not dynamic phase/frequency state.
rf.phaseOffset = phase_offset;
rf.freqOffset = frequency_offset;

return

function adc = set_adc_offsets(adc, phase_offset, frequency_offset)
% SET_ADC_OFFSETS Restore ADC receiver phase/frequency offsets.

adc.phaseOffset = phase_offset;
adc.freqOffset = frequency_offset;

return

function g = scale_gradient_event(g, scale, channel)
% SCALE_GRADIENT_EVENT Scale a normalized Pulseq gradient event.
%
% Handles both arbitrary/sampled gradients and trapezoid/scalar gradients.

if nargin >= 3 && ~isempty(channel)
    g.channel = char(channel);
end

if isfield(g, 'waveform') && ~isempty(g.waveform)
    g.waveform = g.waveform * scale;
end

if isfield(g, 'first') && ~isempty(g.first)
    g.first = g.first * scale;
end

if isfield(g, 'last') && ~isempty(g.last)
    g.last = g.last * scale;
end

if isfield(g, 'amplitude') && ~isempty(g.amplitude)
    g.amplitude = g.amplitude * scale;
end

if isfield(g, 'area') && ~isempty(g.area)
    g.area = g.area * scale;
end

if isfield(g, 'flatArea') && ~isempty(g.flatArea)
    g.flatArea = g.flatArea * scale;
end

return


function events = block_to_events(b)
% BLOCK_TO_EVENTS Convert a Pulseq block struct into an ordered cell array
% of events suitable for seq.addBlock(events{:}).
%
% Important:
%   MATLAB Pulseq determines gradient axis from event.channel, not from the
%   variable name or block field name. Therefore we force b.gx.channel = 'x',
%   b.gy.channel = 'y', and b.gz.channel = 'z' before emitting events.

events = {};

if has_event(b, 'rf')
    events{end+1} = b.rf;
end

if has_event(b, 'gx')
    b.gx = force_gradient_channel(b.gx, 'x');
    events{end+1} = b.gx;
end

if has_event(b, 'gy')
    b.gy = force_gradient_channel(b.gy, 'y');
    events{end+1} = b.gy;
end

if has_event(b, 'gz')
    b.gz = force_gradient_channel(b.gz, 'z');
    events{end+1} = b.gz;
end

if has_event(b, 'adc')
    events{end+1} = b.adc;
end

if isempty(events)
    error('Cannot emit an empty non-delay block.');
end

return

function g = force_gradient_channel(g, channel)
% FORCE_GRADIENT_CHANNEL Set the Pulseq gradient channel field explicitly.
%
% Pulseq addBlock uses g.channel to determine x/y/z. The PulSeg IR stores
% gradients as b.gx, b.gy, b.gz, so the field name is authoritative here.

g.channel = char(channel);

return




function R = get_rotation_matrix_for_event(inst, grad_i)
% GET_ROTATION_MATRIX_FOR_EVENT Return rotation matrix for a gradient event,
% defaulting to identity.

R = eye(3);

if isfield(inst, 'rotation_matrix') && ~isempty(inst.rotation_matrix)
    R = inst.rotation_matrix(:, :, grad_i);
end

return


function tf = is_identity_matrix(R)
% IS_IDENTITY_MATRIX Conservative identity check for 3x3 rotation matrices.

tol = 1e-12;
tf = isequal(size(R), [3 3]) && all(abs(R - eye(3)) < tol, 'all');

return

function val = getfield_default(s, fieldname, default)
% GETFIELD_DEFAULT Return struct field value or default.

if isfield(s, fieldname) && ~isempty(s.(fieldname))
    val = s.(fieldname);
else
    val = default;
end

return
