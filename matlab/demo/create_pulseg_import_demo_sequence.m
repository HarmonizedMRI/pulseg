function seq = create_pulseg_import_demo_sequence(seqFile)
% CREATE_PULSEG_IMPORT_DEMO_SEQUENCE Create a demo Pulseq file for import tests.
%
% Syntax:
%   seq = create_pulseg_import_demo_sequence(seqFile)
%
% Description:
%   Creates a compact Pulseq sequence containing multiple TRID-labeled
%   PulSeg-style segments. The sequence is intentionally designed to test
%   PulSeg base-block normalization and reuse, including signed gradient
%   scale factors.
%
% Segment layout:
%
%   Segment TRID 101, instance 1:
%       block 1: TRID label + RF + slice-select trapezoid
%       block 2: positive trapezoid readout + ADC
%       block 3: pure delay, duration 1 ms
%
%   Segment TRID 101, instance 2:
%       block 1: TRID label + scaled RF + slice-select trapezoid
%       block 2: negative trapezoid readout + ADC
%       block 3: pure delay, duration 2 ms
%
%   Segment TRID 202:
%       block 1: TRID label + positive arbitrary gx/gy gradients
%       block 2: pure delay, duration 0.8 ms
%
%   Segment TRID 203:
%       block 1: TRID label + negative arbitrary gx/gy gradients
%       block 2: pure delay, duration 0.8 ms
%
%   Segment TRID 204:
%       block 1: TRID label + negative trapezoid readout + ADC
%
% Inputs:
%   seqFile
%       Output .seq filename. If empty or omitted, the sequence is created
%       but not written.
%
% Output:
%   seq
%       Pulseq mr.Sequence object.

    if nargin < 1
        seqFile = '';
    end

    %% System definition

    sys = mr.opts( ...
        'MaxGrad', 32, 'GradUnit', 'mT/m', ...
        'MaxSlew', 130, 'SlewUnit', 'T/m/s', ...
        'rfRasterTime', 2e-6, ...
        'gradRasterTime', 4e-6, ...
        'blockDurationRaster', 4e-6, ...
        'rfRingdownTime', 20e-6, ...
        'rfDeadTime', 100e-6, ...
        'adcDeadTime', 10e-6);

    seq = mr.Sequence(sys);

    fov = 220e-3;
    Nx = 64;
    sliceThickness = 5e-3;
    readoutTime = 3.2e-3;

    %% RF + slice-select block

    [rf, gz, gzr] = mr.makeSincPulse( ...
        pi/6, ...
        'Duration', 2e-3, ...
        'SliceThickness', sliceThickness, ...
        'apodization', 0.5, ...
        'timeBwProduct', 4, ...
        'use', 'excitation', ...
        'system', sys);

    % Create a scaled RF instance with identical normalized shape.
    rf_scaled = scale_rf_event(rf, 1.5);

    %% Trapezoid readout + ADC

    gx_ro = mr.makeTrapezoid( ...
        'x', ...
        'FlatArea', Nx / fov, ...
        'FlatTime', readoutTime, ...
        'system', sys);

    adc = mr.makeAdc( ...
        Nx, ...
        'Duration', gx_ro.flatTime, ...
        'Delay', gx_ro.riseTime, ...
        'system', sys);

    gx_ro_neg = scale_gradient_event(gx_ro, -1);

    %% Arbitrary gradients

    nArb = 96;
    u = linspace(0, 1, nArb);

    % Smooth waveform that starts and ends at zero.
    arb_shape = sin(pi * u).^2;

    % Keep arbitrary gradient safely below hardware limits.
    arb_amp_x = 0.10 * sys.maxGrad;
    arb_amp_y = 0.06 * sys.maxGrad;

    gx_arb = mr.makeArbitraryGrad( ...
        'x', ...
        arb_amp_x * arb_shape, ...
        'first', arb_amp_x * arb_shape(1), ...
        'last', arb_amp_x * arb_shape(end), ...
        'system', sys);

    gy_arb = mr.makeArbitraryGrad( ...
        'y', ...
        arb_amp_y * arb_shape, ...
        'first', arb_amp_y * arb_shape(1), ...
        'last', arb_amp_y * arb_shape(end), ...
        'system', sys);

    gx_arb_neg = scale_gradient_event(gx_arb, -1);
    gy_arb_neg = scale_gradient_event(gy_arb, -1);

    %% Delays

    delay_1ms = mr.makeDelay(1e-3);
    delay_2ms = mr.makeDelay(2e-3);
    delay_08ms = mr.makeDelay(0.8e-3);

    %% Segment TRID 101, instance 1

    seq.addBlock(rf, gz, make_trid_label(101));
    seq.addBlock(gx_ro, adc);
    seq.addBlock(delay_1ms);

    %% Segment TRID 101, instance 2
    %
    % Same virtual segment as above, but:
    %   - RF amplitude is scaled
    %   - readout gradient polarity is inverted
    %   - delay duration changes, so block 3 should be variable delay ID 1

    adc2 = adc;
    if isfield(adc2, 'phaseOffset')
        adc2.phaseOffset = pi/4;
    end

    seq.addBlock(rf_scaled, gz, make_trid_label(101));
    seq.addBlock(gx_ro_neg, adc2);
    seq.addBlock(delay_2ms);

    %% Segment TRID 202
    %
    % Positive arbitrary gradients.

    seq.addBlock(gx_arb, gy_arb, make_trid_label(202));
    seq.addBlock(delay_08ms);

    %% Segment TRID 203
    %
    % Negative arbitrary gradients with otherwise identical shape to TRID 202.
    % This should reuse the same base block as TRID 202 block 1.

    seq.addBlock(gx_arb_neg, gy_arb_neg, make_trid_label(203));
    seq.addBlock(delay_08ms);

    %% Segment TRID 204
    %
    % Negative trapezoid readout + ADC. This should reuse the same base block
    % as TRID 101 block 2 if signed trapezoid normalization works.

    seq.addBlock(gx_ro_neg, adc, make_trid_label(204));

    %% Definitions and timing check

    seq.setDefinition('Name', 'pulseg_import_demo');
    seq.setDefinition('FOV', [fov fov sliceThickness]);

    [ok, error_report] = seq.checkTiming;

    if ~ok
        if iscell(error_report)
            error_msg = strjoin(error_report, newline);
        else
            error_msg = char(error_report);
        end

        error('Generated demo sequence failed Pulseq timing check:%s%s', newline, error_msg);
    end

    %% Write file if requested

    if ~isempty(seqFile)
        seq.write(seqFile);
    end
end


function label = make_trid_label(trid)
% MAKE_TRID_LABEL Create a Pulseq TRID label event.

    label = mr.makeLabel('SET', 'TRID', trid);
end


function rf2 = scale_rf_event(rf, scale)
% SCALE_RF_EVENT Scale an RF event's signal while preserving shape metadata.

    rf2 = rf;

    if isfield(rf2, 'signal') && ~isempty(rf2.signal)
        rf2.signal = scale * rf2.signal;
    end
end

function g = add_gradient_edge_fields(g)
% ADD_GRADIENT_EDGE_FIELDS Add Pulseq arbitrary-gradient edge values.
%
% Newer Pulseq versions require arbitrary gradient events to include
% first/last fields. These represent the gradient amplitudes at the raster
% edges surrounding the sampled waveform.

    if isfield(g, 'waveform') && ~isempty(g.waveform)
        if ~isfield(g, 'first') || isempty(g.first)
            g.first = g.waveform(1);
        end

        if ~isfield(g, 'last') || isempty(g.last)
            g.last = g.waveform(end);
        end
    end
end



function g2 = scale_gradient_event(g, scale)
% SCALE_GRADIENT_EVENT Scale a Pulseq gradient event by a scalar factor.
%
% This local helper avoids relying on mr.scaleGrad so that the test is less
% sensitive to Pulseq toolbox version differences.

    g2 = g;

    fields_to_scale = { ...
        'amplitude', ...
        'area', ...
        'flatArea', ...
        'waveform', ...
        'first', ...
        'last'};

    for k = 1:numel(fields_to_scale)
        fname = fields_to_scale{k};

        if isfield(g2, fname) && ~isempty(g2.(fname))
            g2.(fname) = scale * g2.(fname);
        end
    end
end


function vs = get_virtual_segment_by_trid(pulseg_ir, trid)
% GET_VIRTUAL_SEGMENT_BY_TRID Return virtual segment with matching TRID metadata.
%
% This helper assumes pulseg.import stores optional TRID metadata:
%
%   pulseg_ir.virtual_segments(i).TRID
%
% If that metadata is later removed for strict spec minimalism, this helper
% can be replaced by name-based lookup or by another test-side mapping.

    for i = 1:numel(pulseg_ir.virtual_segments)
        if isfield(pulseg_ir.virtual_segments(i), 'TRID') && ...
                pulseg_ir.virtual_segments(i).TRID == trid
            vs = pulseg_ir.virtual_segments(i);
            return;
        end
    end

    error('Could not find virtual segment with TRID %d.', trid);
end


function grad_amp = collect_gradient_amplitudes(pulseg_ir)
% COLLECT_GRADIENT_AMPLITUDES Concatenate gradient amplitudes from execution stream.

    grad_amp = [];

    for k = 1:numel(pulseg_ir.execution_stream)
        gk = pulseg_ir.execution_stream(k).gradient_amplitude;

        if ~isempty(gk)
            % Accept either 3 x N or N x 3 layout.
            grad_amp = [grad_amp; gk(:).']; %#ok<AGROW>
        end
    end
end


function cleanup_temp_dir(tmpDir)
% CLEANUP_TEMP_DIR Remove temporary test directory.

    if isfolder(tmpDir)
        rmdir(tmpDir, 's');
    end
end
