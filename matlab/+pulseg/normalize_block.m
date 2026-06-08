function [b0, scales] = normalize_block(b)
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
end
