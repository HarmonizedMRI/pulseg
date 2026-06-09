function tests = test_import_demo_sequence
% TEST_IMPORT_DEMO_SEQUENCE Formal tests for pulseg.import using a generated demo .seq.
%
% This test creates a small Pulseq sequence with several PulSeg-style TRID
% segments, writes it to a temporary .seq file, imports it with pulseg.import,
% and checks that the resulting PulSeg IR is structurally valid and exercises
% key PulSeg 2.0 behavior.
%
% The generated demo sequence intentionally contains:
%   - RF + slice-select trapezoid segment
%   - trapezoid readout gradient with ADC
%   - variable pure delay block
%   - arbitrary gradient segment
%   - sign-flipped arbitrary gradient segment
%   - sign-flipped trapezoid gradient segment
%
% Required external dependency:
%   - MATLAB Pulseq toolbox, providing mr.Sequence, mr.opts, mr.makeLabel, etc.
%
% Suggested location:
%   tests/test_import_demo_sequence.m

tests = functiontests(localfunctions);
end


function testPulsegImportDemoSequence(testCase)
% Create a demo .seq file and verify pulseg.import returns a PulSeg 2.0 IR.

    % Skip gracefully if Pulseq is not available.
    testCase.assumeTrue( ...
        exist('mr.Sequence', 'class') == 8 || exist('mr.Sequence', 'file') == 2, ...
        'Pulseq MATLAB toolbox was not found on the MATLAB path.');

    testCase.assumeTrue( ...
        exist('pulseg.import', 'file') == 2 || exist('+pulseg/import.m', 'file') == 2, ...
        'pulseg.import was not found on the MATLAB path.');

    % Create temporary output directory.
    tmpDir = tempname;
    mkdir(tmpDir);
    cleanupObj = onCleanup(@() cleanup_temp_dir(tmpDir)); %#ok<NASGU>

    seqFile = fullfile(tmpDir, 'pulseg_import_demo.seq');

    % Create and write demo Pulseq sequence.
    addpath ../demo/
    create_pulseg_import_demo_sequence(seqFile);

    testCase.verifyTrue(isfile(seqFile), 'Demo .seq file was not created.');

    % Import with PulSeg.
    pulseg_ir = pulseg.import(seqFile, 'verbose', false);

    %% Top-level PulSeg 2.0 checks

    testCase.verifyTrue(isstruct(pulseg_ir));
    testCase.verifyTrue(isfield(pulseg_ir, 'pulseg_version'));
    testCase.verifyEqual(pulseg_ir.pulseg_version, '2.0');

    testCase.verifyTrue(isfield(pulseg_ir, 'base_blocks'));
    testCase.verifyTrue(isfield(pulseg_ir, 'virtual_segments'));
    testCase.verifyTrue(isfield(pulseg_ir, 'execution_stream'));

    testCase.verifyNotEmpty(pulseg_ir.base_blocks);
    testCase.verifyNotEmpty(pulseg_ir.virtual_segments);
    testCase.verifyNotEmpty(pulseg_ir.execution_stream);

    %% BaseBlock ID checks

    base_ids = [pulseg_ir.base_blocks.id];

    testCase.verifyTrue(all(base_ids >= 2), ...
        'Explicit base block IDs must be >= 2.');
    testCase.verifyEqual(numel(unique(base_ids)), numel(base_ids), ...
        'Explicit base block IDs must be unique.');

    %% VirtualSegment checks

    vs_ids = [pulseg_ir.virtual_segments.id];

    testCase.verifyTrue(all(vs_ids > 0), ...
        'Virtual segment IDs must be positive.');
    testCase.verifyEqual(numel(unique(vs_ids)), numel(vs_ids), ...
        'Virtual segment IDs must be unique.');

    valid_base_ids = [0 1 base_ids];

    for s = 1:numel(pulseg_ir.virtual_segments)
        ids = pulseg_ir.virtual_segments(s).base_block_ids;

        testCase.verifyNotEmpty(ids, ...
            sprintf('virtual_segments(%d).base_block_ids is empty.', s));

        testCase.verifyTrue(all(ismember(ids, valid_base_ids)), ...
            sprintf('virtual_segments(%d) references invalid base block IDs.', s));
    end

    %% Execution stream checks

    for k = 1:numel(pulseg_ir.execution_stream)
        testCase.verifyTrue( ...
            ismember(pulseg_ir.execution_stream(k).virtual_segment_id, vs_ids), ...
            sprintf('execution_stream(%d) references invalid virtual_segment_id.', k));

        testCase.verifyTrue(isfield(pulseg_ir.execution_stream(k), 'rf_amplitude'));
        testCase.verifyTrue(isfield(pulseg_ir.execution_stream(k), 'gradient_amplitude'));
        testCase.verifyTrue(isfield(pulseg_ir.execution_stream(k), 'block_duration'));
    end

    %% Check expected segment behavior

    % This demo writes five segment instances:
    %   TRID 101 twice
    %   TRID 202 once
    %   TRID 203 once
    %   TRID 204 once
    testCase.verifyEqual(numel(pulseg_ir.execution_stream), 5, ...
        'Unexpected number of segment instances in execution_stream.');

    % Verify variable delay block was detected somewhere.
    all_segment_base_ids = [pulseg_ir.virtual_segments.base_block_ids];
    testCase.verifyTrue(any(all_segment_base_ids == 1), ...
        'Expected at least one implicit variable delay base block ID == 1.');

    % Verify constant delay block exists somewhere.
    testCase.verifyTrue(any(all_segment_base_ids == 0), ...
        'Expected at least one implicit constant delay base block ID == 0.');

    %% Sign-flipped arbitrary gradient reuse check

    % TRID 202 and TRID 203 are deliberately identical except for gradient
    % polarity in their first arbitrary-gradient block. If normalize_block()
    % canonicalizes polarity and compare_normalized_blocks() compares
    % normalized shapes, these should share the same base block ID.
    vs202 = get_virtual_segment_by_trid(pulseg_ir, 202);
    vs203 = get_virtual_segment_by_trid(pulseg_ir, 203);

    testCase.verifyEqual(vs202.base_block_ids(1), vs203.base_block_ids(1), ...
        ['Sign-flipped arbitrary gradients did not reuse the same base block. ', ...
         'Check normalize_block() and compare_normalized_blocks().']);

    %% Sign-flipped trapezoid gradient reuse check

    % TRID 101 block 2 is a positive trapezoid readout + ADC.
    % TRID 204 block 1 is the corresponding negative trapezoid readout + ADC.
    % These should share a base block if signed gradient scaling is working.
    vs101 = get_virtual_segment_by_trid(pulseg_ir, 101);
    vs204 = get_virtual_segment_by_trid(pulseg_ir, 204);

    testCase.verifyEqual(vs101.base_block_ids(2), vs204.base_block_ids(1), ...
        ['Sign-flipped trapezoid gradients did not reuse the same base block. ', ...
         'Check trapezoid normalization and normalized block comparison.']);

    %% Verify negative gradient amplitudes are present in execution_stream

    all_grad_amp = collect_gradient_amplitudes(pulseg_ir);

    testCase.verifyTrue(any(all_grad_amp(:) < 0), ...
        'Expected at least one negative gradient amplitude scale factor.');

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
