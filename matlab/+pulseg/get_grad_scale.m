function scale = get_grad_scale(g)
% GET_GRAD_SCALE Returns the signed maximum amplitude of a Pulseq gradient
%
% Input:
%   g - A Pulseq gradient structure (either trapezoid or arbitrary)
%
% Output:
%   scale - The signed maximum amplitude (value with largest absolute value,
%           preserving sign). If positive and negative peaks have equal
%           magnitude, the positive value is returned.
%
% Supports:
%   - Trapezoid gradients (g.type == 'trap')
%   - Arbitrary gradients (g.type == 'grad')

    if ~isstruct(g)
        error('get_grad_scale:invalidInput', 'Input must be a Pulseq gradient structure.');
    end

    if ~isfield(g, 'type')
        error('get_grad_scale:missingField', 'Gradient structure must have a ''type'' field.');
    end

    switch g.type
        case 'trap'
            if ~isfield(g, 'amplitude')
                error('get_grad_scale:missingField', 'Trapezoid gradient must have an ''amplitude'' field.');
            end
            scale = g.amplitude;

        case 'grad'
            if ~isfield(g, 'waveform')
                error('get_grad_scale:missingField', 'Arbitrary gradient must have a ''waveform'' field.');
            end
            pos_peak = max(g.waveform);
            neg_peak = min(g.waveform);

            if abs(pos_peak) >= abs(neg_peak)
                scale = pos_peak;
            else
                scale = neg_peak;
            end

        otherwise
            error('get_grad_scale:unknownType', ...
                'Unknown gradient type ''%s''. Expected ''trap'' or ''grad''.', g.type);
    end

end
