function [b0, scales] = normalize_block(b)
% NORMALIZE_BLOCK Normalize RF and gradient amplitudes in a Pulseq block.
%
% Syntax:
%   [b0, scales] = pulseg.normalize_block(b)
%
% Description:
%   NORMALIZE_BLOCK takes a Pulseq block structure and returns a normalized
%   copy suitable for use as a PulSeg 2.0 BaseBlock. The returned block b0
%   preserves the waveform shapes, timing, ADC information, and other event
%   metadata from the input block, but normalizes RF and gradient amplitudes
%   according to the PulSeg IR specification.
%
%   RF waveforms are normalized by their global peak magnitude:
%
%       max(abs(b0.rf.signal(:))) == 1
%
%   for nonzero RF events. This also supports multi-channel RF/pTx arrays by
%   using a single global scale factor across all RF samples and channels,
%   thereby preserving relative amplitudes between transmit channels.
%
%   Gradient events are normalized independently for each logical gradient
%   axis, gx, gy, and gz. If a gradient event contains a sampled waveform
%   field, the waveform is normalized by its peak absolute value. If it does
%   not contain a waveform field but contains an amplitude field, the scalar
%   amplitude is normalized by its absolute value. Empty or missing gradient
%   channels are left unchanged and receive a scale factor of zero.
%
% Inputs:
%   b
%       Pulseq block structure, typically returned by seq.getBlock(n).
%       The block may contain fields such as:
%
%           b.rf
%           b.gx
%           b.gy
%           b.gz
%           b.adc
%
% Outputs:
%   b0
%       Normalized copy of the input block. RF and gradient amplitudes are
%       divided by their corresponding scale factors. Channels with zero
%       scale factors are left unchanged to avoid division by zero.
%
%   scales
%       Structure containing the physical amplitude scale factors removed
%       from the block:
%
%           scales.rf
%               RF peak magnitude scale factor. Empty if no RF event is
%               present.
%
%           scales.grad
%               1-by-3 vector of gradient scale factors:
%
%                   [gx_scale, gy_scale, gz_scale]
%
%               A value of zero indicates that the corresponding gradient
%               channel is absent or has zero amplitude.
%
% Notes:
%   - ADC events are not normalized and are copied directly into b0.
%   - RF phase offsets, RF frequency offsets, ADC phase offsets, and ADC
%     frequency offsets are not modified by this function.
%   - For PulSeg 2.0, the returned b0 is intended to define waveform shape,
%     while the returned scale factors are intended to be stored in the
%     corresponding SegmentInstance amplitude fields.
%   - This function does not validate scanner hardware limits, slew rates,
%     dead times, or raster alignment.
%
% Example:
%   b = seq.getBlock(42);
%   [b0, scales] = pulseg.normalize_block(b);
%
%   % Recover original RF signal, for a nonzero RF event:
%   rf_signal_original = b0.rf.signal * scales.rf;
%
%   % Recover original gx waveform, for a nonzero arbitrary gradient:
%   gx_waveform_original = b0.gx.waveform * scales.grad(1);
%
% See also:
%   pulseg.import

b0 = b;

scales.rf = [];
scales.grad = [0 0 0];

% RF
if isfield(b, 'rf') && ~isempty(b.rf)
    s = max(abs(b.rf.signal(:)));
    scales.rf = s;

    if s > 0
        b0.rf.signal = b.rf.signal / s;
    end
end

% Gradients
grad_fields = {'gx', 'gy', 'gz'};

for a = 1:3
    gname = grad_fields{a};

    if isfield(b, gname) && ~isempty(b.(gname))
        g = b.(gname);

        if isfield(g, 'waveform')
            s = max(abs(g.waveform(:)));
            scales.grad(a) = s;

            if s > 0
                b0.(gname).waveform = g.waveform / s;
            end

        elseif isfield(g, 'amplitude')
            s = abs(g.amplitude);
            scales.grad(a) = s;

            if s > 0
                b0.(gname).amplitude = g.amplitude / s;
            end
        end
    end
end
