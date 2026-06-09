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
%   This behavior is useful for PulSeg because positive and negative
%   instances of the same gradient shape can share one BaseBlock.
%
% Inputs:
%   b
%       Pulseq block structure, typically from seq.getBlock(n).
%
% Outputs:
%   b0
%       Normalized copy of b. RF and gradient amplitudes are normalized.
%       ADC events and other non-amplitude metadata are copied unchanged.
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
%   - ADC events are not normalized.
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
    if isfield(b0.rf, 'phaseOffset'), b0.rf.phaseOffset = 0; end
    if isfield(b0.rf, 'freqOffset'),  b0.rf.freqOffset  = 0; end
end

%% ADC
if isfield(b0, 'adc') && ~isempty(b0.adc)
    if isfield(b0.adc, 'phaseOffset'), b0.adc.phaseOffset = 0; end
    if isfield(b0.adc, 'freqOffset'),  b0.adc.freqOffset  = 0; end
end

%% Gradients
grad_fields = {'gx', 'gy', 'gz'};

for a = 1:3
    gname = grad_fields{a};

    if isfield(b, gname) && ~isempty(b.(gname))
        g = b.(gname);

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
    end
end
