function E = get_grad_energy(g, scale)
% GET_GRAD_ENERGY Compute scaled gradient energy for a single gradient channel.
%
% Energy is defined as sum(waveform.^2) * dt, scaled by the square of the
% amplitude scaling factor. Units are (T/m)^2 * s.
%
% Input
%   g      Pulseq gradient struct with normalized waveform amplitude (peak == 1.0).
%          May be an arbitrary gradient (with .waveform) or a trapezoid (with
%          .riseTime, .flatTime, .fallTime).
%   scale  Amplitude scaling factor from the segment instance

if isempty(g)
    E = 0;
    return;
end

if strcmp(g.type, 'trap')
    amp = g.amplitude;
    E = (g.amplitude)^2 / 3 * g.riseTime ...   % (Hz/m)^2*sec
           + (g.amplitude)^2 * g.flatTime ... 
           + (g.amplitude)^2 / 3 * g.fallTime;
else  % arbitrary gradient or extended trapezoid
    E = sum((g.waveform(1:end-1)).^2 .* diff(g.tt));
end

E = scale^2 * E;

