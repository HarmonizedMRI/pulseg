function issame = compare_normalized_blocks(b1, b2, varargin)
% COMPARE_NORMALIZED_BLOCKS Compare two normalized Pulseq blocks by shape.
%
% Syntax:
%   issame = pulseg.compare_normalized_blocks(b1, b2)
%   issame = pulseg.compare_normalized_blocks(b1, b2, tol)
%
% Description:
%   COMPARE_NORMALIZED_BLOCKS compares two Pulseq block structs after they
%   have already been normalized with pulseg.normalize_block(). The intended
%   use is to determine whether two physical blocks can share the same
%   PulSeg BaseBlock.
%
%   This function compares structural/timing information and normalized
%   waveform shape. It intentionally does not compare dynamic instance
%   parameters such as RF phase offset, RF frequency offset, ADC phase
%   offset, or ADC frequency offset, since those are stored in the PulSeg
%   SegmentInstance.
%
% Inputs:
%   b1, b2
%       Normalized Pulseq block structs.
%
%   tol
%       Optional numeric tolerance. Default is 1e-12.
%
% Output:
%   issame
%       Logical true if the two normalized blocks are considered equivalent
%       for PulSeg BaseBlock reuse; false otherwise.
%
% Notes:
%   - Gradient polarity inversion can share a base block if
%     normalize_block() canonicalizes polarity into a signed scale factor.
%   - ADC phase/frequency offsets are ignored by this comparison.
%   - RF phase/frequency offsets are ignored by this comparison.
%
% See also:
%   pulseg.normalize_block
%   pulseg.import

    if nargin >= 3
        tol = varargin{1};
    else
        tol = 1e-12;
    end

    issame = true;

    %% Compare block duration if present
    if has_field(b1, 'blockDuration') || has_field(b2, 'blockDuration')
        if ~(has_field(b1, 'blockDuration') && has_field(b2, 'blockDuration'))
            issame = false;
            return;
        end

        if abs(b1.blockDuration - b2.blockDuration) > tol
            issame = false;
            return;
        end
    end

    %% Compare RF events by normalized signal shape and RF timing
    if ~compare_rf(get_event(b1, 'rf'), get_event(b2, 'rf'), tol)
        issame = false;
        return;
    end

    %% Compare gradients by normalized shape and timing
    grad_fields = {'gx', 'gy', 'gz'};

    for a = 1:numel(grad_fields)
        gname = grad_fields{a};

        if ~compare_gradient(get_event(b1, gname), get_event(b2, gname), tol)
            issame = false;
            return;
        end
    end

    %% Compare ADC event-defining fields
    if ~compare_adc(get_event(b1, 'adc'), get_event(b2, 'adc'), tol)
        issame = false;
        return;
    end

    %% Optional: compare trigger presence/type if you want trigger blocks to be distinct
    %
    % If physio triggers are stored only at the SegmentInstance level, leave
    % this ignored. If triggers are part of the reusable block structure,
    % uncomment and implement compare_trigger().
    %
    % if ~compare_trigger(get_event(b1, 'trig'), get_event(b2, 'trig'))
    %     issame = false;
    %     return;
    % end
end


function tf = compare_rf(rf1, rf2, tol)
% Compare normalized RF events.

    tf = true;

    if isempty(rf1) && isempty(rf2)
        return;
    end

    if xor(isempty(rf1), isempty(rf2))
        tf = false;
        return;
    end

    % Normalized RF waveform shape.
    if ~same_field_array(rf1, rf2, 'signal', tol)
        tf = false;
        return;
    end

    % RF timing/shape-defining fields, if present.
    % Do not compare phaseOffset/freqOffset because those are instance params.
    scalar_fields = {
        'delay'
    };

    if ~same_scalar_fields(rf1, rf2, scalar_fields, tol)
        tf = false;
        return;
    end

    % Optional RF time axis, if present.
    if has_field(rf1, 't') || has_field(rf2, 't')
        if ~same_field_array(rf1, rf2, 't', tol)
            tf = false;
            return;
        end
    end
end


function tf = compare_gradient(g1, g2, tol)
% Compare normalized gradient events.

    tf = true;

    if isempty(g1) && isempty(g2)
        return;
    end

    if xor(isempty(g1), isempty(g2))
        tf = false;
        return;
    end

    % If both have a type field, require the same type.
    if has_field(g1, 'type') || has_field(g2, 'type')
        if ~(has_field(g1, 'type') && has_field(g2, 'type'))
            tf = false;
            return;
        end

        if ~strcmp(g1.type, g2.type)
            tf = false;
            return;
        end
    end

    % Sampled/arbitrary gradient waveform.
    if has_field(g1, 'waveform') || has_field(g2, 'waveform')
        if ~same_field_array(g1, g2, 'waveform', tol)
            tf = false;
            return;
        end
    end

    % Trapezoid/scalar normalized amplitude.
    % After normalize_block(), this may be +1 for canonicalized gradients.
    if has_field(g1, 'amplitude') || has_field(g2, 'amplitude')
        if ~same_field_scalar(g1, g2, 'amplitude', tol)
            tf = false;
            return;
        end
    end

    % Gradient timing/shape-defining fields.
    scalar_fields = {
        'delay'
        'riseTime'
        'flatTime'
        'fallTime'
    };

    if ~same_scalar_fields(g1, g2, scalar_fields, tol)
        tf = false;
        return;
    end

    % Extended trapezoid / arbitrary time vector, if present.
    if has_field(g1, 'tt') || has_field(g2, 'tt')
        if ~same_field_array(g1, g2, 'tt', tol)
            tf = false;
            return;
        end
    end

    if has_field(g1, 'time') || has_field(g2, 'time')
        if ~same_field_array(g1, g2, 'time', tol)
            tf = false;
            return;
        end
    end
end


function tf = compare_adc(adc1, adc2, tol)
% Compare ADC event-defining fields.
%
% Phase and frequency offsets are intentionally ignored because they are
% dynamic SegmentInstance fields in PulSeg.

    tf = true;

    if isempty(adc1) && isempty(adc2)
        return;
    end

    if xor(isempty(adc1), isempty(adc2))
        tf = false;
        return;
    end

    scalar_fields = {
        'numSamples'
        'dwell'
        'delay'
        'duration'
    };

    if ~same_scalar_fields(adc1, adc2, scalar_fields, tol)
        tf = false;
        return;
    end
end


function e = get_event(b, fieldname)
% Safely get a block event field. Return [] if absent or empty.

    if isfield(b, fieldname) && ~isempty(b.(fieldname))
        e = b.(fieldname);
    else
        e = [];
    end
end


function tf = has_field(s, fieldname)
% True if struct has a nonempty field.

    tf = isstruct(s) && isfield(s, fieldname) && ~isempty(s.(fieldname));
end


function tf = same_scalar_fields(s1, s2, fieldnames, tol)
% Compare a list of optional scalar numeric fields.

    tf = true;

    for k = 1:numel(fieldnames)
        fname = fieldnames{k};

        if has_field(s1, fname) || has_field(s2, fname)
            if ~same_field_scalar(s1, s2, fname, tol)
                tf = false;
                return;
            end
        end
    end
end


function tf = same_field_scalar(s1, s2, fieldname, tol)
% Compare one optional scalar field.

    tf = true;

    has1 = has_field(s1, fieldname);
    has2 = has_field(s2, fieldname);

    if has1 ~= has2
        tf = false;
        return;
    end

    if ~has1
        return;
    end

    v1 = s1.(fieldname);
    v2 = s2.(fieldname);

    if ~(isscalar(v1) && isscalar(v2))
        tf = false;
        return;
    end

    if isnumeric(v1) && isnumeric(v2)
        tf = abs(v1 - v2) <= tol;
    else
        tf = isequal(v1, v2);
    end
end


function tf = same_field_array(s1, s2, fieldname, tol)
% Compare one optional array field.

    tf = true;

    has1 = has_field(s1, fieldname);
    has2 = has_field(s2, fieldname);

    if has1 ~= has2
        tf = false;
        return;
    end

    if ~has1
        return;
    end

    v1 = s1.(fieldname);
    v2 = s2.(fieldname);

    if ~isequal(size(v1), size(v2))
        tf = false;
        return;
    end

    if isnumeric(v1) && isnumeric(v2)
        tf = all(abs(v1(:) - v2(:)) <= tol);
    else
        tf = isequal(v1, v2);
    end
end
