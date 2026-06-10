function [b0, scales] = normalize_block(b)
% NORMALIZE_BLOCK Normalize RF and gradient amplitudes in a Pulseq block.
%
% Syntax:
%   [b0, scales] = pulseg.normalize_block(b)
%
% Description:
%   NORMALIZE_BLOCK returns a normalized copy of a Pulseq block and the
%   amplitude scale factors needed to reconstruct the original physical
%   block.
%
%   RF events are normalized by their global peak magnitude. The RF scale
%   factor is nonnegative.
%
%   Gradient events are normalized independently for gx, gy, and gz. For
%   gradients, the scale factor is signed. This means that polarity-inverted
%   gradient waveforms normalize to the same canonical base-block shape and
%   differ only by the sign of the corresponding entry in scales.grad.
%
%   In addition to the primary gradient waveform or amplitude field,
%   amplitude-like gradient metadata fields are normalized by the same signed
%   scale factor when present:
%
%       first
%       last
%       area
%       flatArea
%
%   This is important because recent Pulseq versions use first/last to store
%   gradient values at raster edges, and trapezoid events may carry area and
%   flatArea fields.
%
% Inputs:
%   b
%       Pulseq block structure, typically from seq.getBlock(n).
%
% Outputs:
%   b0
%       Normalized copy of b. RF and gradient amplitudes are normalized.
%       ADC events and other non-amplitude metadata are copied unchanged,
%       except dynamic RF/ADC phase and frequency offsets are zeroed.
%
%   scales
%       Struct containing removed amplitude scale factors:
%
%           scales.rf
%               RF peak magnitude scale factor. Empty if no RF event exists.
%
%           scales.grad
%               1-by-3 vector of signed gradient scale factors:
%
%                   [gx_scale, gy_scale, gz_scale]
%
%               Missing or zero-valued gradient channels receive scale 0.
%
% Notes:
%   - RF normalization uses magnitude and therefore does not absorb RF phase.
%   - Gradient normalization uses signed scaling so that globally inverted
%     gradient waveforms share the same normalized shape.
%   - RF/ADC phase and frequency offsets are zeroed in b0 because these are
%     represented in SegmentInstance fields in PulSeg 2.0.
%   - ADC events are otherwise not normalized.
%   - This function does not check hardware limits or slew constraints.

b0 = b;

scales.rf = [];
scales.grad = [0 0 0];

%% RF

if isfield(b, 'rf') && ~isempty(b.rf)
    s = max(abs(b.rf.signal(:)));
    scales.rf = s;

    if s > 0
        b0.rf.signal = b.rf.signal / s;
    end

    % Dynamic RF offsets belong in SegmentInstance, not BaseBlock.
    if isfield(b0.rf, 'phaseOffset')
        b0.rf.phaseOffset = 0;
    end
    if isfield(b0.rf, 'freqOffset')
        b0.rf.freqOffset = 0;
    end
end

%% ADC

if isfield(b0, 'adc') && ~isempty(b0.adc)
    % Dynamic ADC offsets belong in SegmentInstance, not BaseBlock.
    if isfield(b0.adc, 'phaseOffset')
        b0.adc.phaseOffset = 0;
    end
    if isfield(b0.adc, 'freqOffset')
        b0.adc.freqOffset = 0;
    end
end

%% Gradients

grad_fields = {'gx', 'gy', 'gz'};

for a = 1:3
    gname = grad_fields{a};

    if isfield(b, gname) && ~isempty(b.(gname))
        g = b.(gname);

        s = 0;

        if isfield(g, 'waveform') && ~isempty(g.waveform)
            % Use signed value at the peak absolute magnitude.
            % This makes g and -g normalize to the same canonical shape.
            [peak_abs, idx] = max(abs(g.waveform(:)));

            if peak_abs > 0
                s = g.waveform(idx);      % signed scale
                scales.grad(a) = s;

                b0.(gname).waveform = g.waveform / s;
            else
                scales.grad(a) = 0;
            end

        elseif isfield(g, 'amplitude') && ~isempty(g.amplitude)
            % Scalar/trapezoid-like gradient amplitude.
            % Preserve polarity in the scale factor.
            s = g.amplitude;

            if s ~= 0
                scales.grad(a) = s;
                b0.(gname).amplitude = 1;
            else
                scales.grad(a) = 0;
            end
        end

        % Normalize amplitude-like gradient metadata using the same signed
        % scale factor. This keeps sign-flipped gradients structurally
        % identical after normalization.
        if s ~= 0
            b0.(gname) = normalize_gradient_amplitude_like_fields(b0.(gname), g, s);
        end
    end
end
end


function g0 = normalize_gradient_amplitude_like_fields(g0, g, s)
% NORMALIZE_GRADIENT_AMPLITUDE_LIKE_FIELDS Normalize dependent gradient fields.
%
% These fields scale linearly with gradient amplitude and therefore should
% be divided by the same signed scale used for waveform/amplitude.

    fields_to_normalize = { ...
        'first', ...
        'last', ...
        'area', ...
        'flatArea'};

    for k = 1:numel(fields_to_normalize)
        fname = fields_to_normalize{k};

        if isfield(g, fname) && ~isempty(g.(fname))
            g0.(fname) = g.(fname) / s;
        end
    end
end
