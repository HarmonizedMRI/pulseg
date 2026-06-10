function tests = test_normalize_block
% TEST_NORMALIZE_BLOCK Unit tests for pulseg.normalize_block.
%
% These tests assume PulSeg 2.0 normalization semantics:
%
%   - RF waveforms are normalized by nonnegative global peak magnitude.
%   - Gradient waveforms are normalized by a signed scale factor equal to
%     the waveform value at the peak absolute magnitude.
%   - Gradient scalar amplitudes are normalized by the signed amplitude.
%   - Sign-flipped gradient waveforms should normalize to the same base
%     shape and differ only in scales.grad.
%   - RF/ADC dynamic phase/frequency offsets are zeroed in the normalized
%     base block, because those values belong in SegmentInstance fields.
%   - ADC events are otherwise copied through.

    tests = functiontests(localfunctions);
end

%% ------------------------------------------------------------------------
%  Helper
%% ------------------------------------------------------------------------

function b = make_empty_block()
    b = struct();
end

%% ------------------------------------------------------------------------
%  RF tests
%% ------------------------------------------------------------------------

function test_rf_normalizes_signal(testCase)
    b.rf.signal = [2, -4, 6];

    [b0, scales] = pulseg.normalize_block(b);

    verifyEqual(testCase, scales.rf, 6, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.rf.signal, [2/6, -4/6, 1], 'AbsTol', 1e-10);
end


function test_rf_already_normalized(testCase)
    b.rf.signal = [0.5, -1.0, 0.25];

    [b0, scales] = pulseg.normalize_block(b);

    verifyEqual(testCase, scales.rf, 1.0, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.rf.signal, b.rf.signal, 'AbsTol', 1e-10);
end


function test_rf_zero_signal_no_division(testCase)
    b.rf.signal = [0, 0, 0];

    [b0, scales] = pulseg.normalize_block(b);

    verifyEqual(testCase, scales.rf, 0, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.rf.signal, [0, 0, 0], 'AbsTol', 1e-10);
end


function test_rf_complex_signal(testCase)
    b.rf.signal = [3+4i, -1+0i];   % max |.| = 5

    [b0, scales] = pulseg.normalize_block(b);

    verifyEqual(testCase, scales.rf, 5, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.rf.signal, b.rf.signal / 5, 'AbsTol', 1e-10);
end


function test_rf_multichannel_global_scale(testCase)
    % pTx-style RF array. Normalization should use one global scale across
    % all samples/channels, not independent per-channel scaling.
    b.rf.signal = [ ...
        1,  2,  3; ...
        4, -8,  2];

    [b0, scales] = pulseg.normalize_block(b);

    verifyEqual(testCase, scales.rf, 8, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.rf.signal, b.rf.signal / 8, 'AbsTol', 1e-10);
    verifyEqual(testCase, max(abs(b0.rf.signal(:))), 1, 'AbsTol', 1e-10);
end


function test_no_rf_field(testCase)
    b = make_empty_block();

    [~, scales] = pulseg.normalize_block(b);

    verifyEmpty(testCase, scales.rf);
end


function test_rf_empty_field(testCase)
    b.rf = [];

    [~, scales] = pulseg.normalize_block(b);

    verifyEmpty(testCase, scales.rf);
end


function test_rf_dynamic_offsets_zeroed(testCase)
    b.rf.signal = [0, 2, 4];
    b.rf.phaseOffset = pi/3;
    b.rf.freqOffset = 123.45;

    [b0, scales] = pulseg.normalize_block(b);

    verifyEqual(testCase, scales.rf, 4, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.rf.signal, b.rf.signal / 4, 'AbsTol', 1e-10);

    verifyTrue(testCase, isfield(b0.rf, 'phaseOffset'));
    verifyTrue(testCase, isfield(b0.rf, 'freqOffset'));
    verifyEqual(testCase, b0.rf.phaseOffset, 0, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.rf.freqOffset, 0, 'AbsTol', 1e-10);
end

%% ------------------------------------------------------------------------
%  ADC offset tests
%% ------------------------------------------------------------------------

function test_adc_dynamic_offsets_zeroed(testCase)
    b.adc.numSamples = 64;
    b.adc.dwell = 10e-6;
    b.adc.delay = 20e-6;
    b.adc.phaseOffset = pi/4;
    b.adc.freqOffset = -321;

    [b0, scales] = pulseg.normalize_block(b);

    verifyEmpty(testCase, scales.rf);
    verifyEqual(testCase, scales.grad, [0 0 0], 'AbsTol', 1e-10);

    verifyEqual(testCase, b0.adc.numSamples, b.adc.numSamples);
    verifyEqual(testCase, b0.adc.dwell, b.adc.dwell, 'AbsTol', 1e-12);
    verifyEqual(testCase, b0.adc.delay, b.adc.delay, 'AbsTol', 1e-12);

    verifyTrue(testCase, isfield(b0.adc, 'phaseOffset'));
    verifyTrue(testCase, isfield(b0.adc, 'freqOffset'));
    verifyEqual(testCase, b0.adc.phaseOffset, 0, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.adc.freqOffset, 0, 'AbsTol', 1e-10);
end

%% ------------------------------------------------------------------------
%  Gradient - waveform tests with signed scaling
%% ------------------------------------------------------------------------

function test_gx_waveform_signed_negative_peak(testCase)
    % Peak absolute value occurs at -20, so signed scale should be -20.
    % This canonicalizes the normalized peak to +1.
    b.gx.waveform = [10, -20, 5];

    [b0, scales] = pulseg.normalize_block(b);

    verifyEqual(testCase, scales.grad(1), -20, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.gx.waveform, [-0.5, 1, -0.25], 'AbsTol', 1e-10);
end


function test_gy_waveform_signed_negative_first_peak(testCase)
    % Tie in abs peak: MATLAB max returns first occurrence, which is -3.
    b.gy.waveform = [-3, 0, 3];

    [b0, scales] = pulseg.normalize_block(b);

    verifyEqual(testCase, scales.grad(2), -3, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.gy.waveform, [1, 0, -1], 'AbsTol', 1e-10);
end


function test_gz_waveform_positive_peak(testCase)
    b.gz.waveform = [0, 7, -7];

    [b0, scales] = pulseg.normalize_block(b);

    verifyEqual(testCase, scales.grad(3), 7, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.gz.waveform, [0, 1, -1], 'AbsTol', 1e-10);
end


function test_grad_waveform_zero_no_division(testCase)
    b.gx.waveform = [0, 0, 0];

    [b0, scales] = pulseg.normalize_block(b);

    verifyEqual(testCase, scales.grad(1), 0, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.gx.waveform, [0, 0, 0], 'AbsTol', 1e-10);
end


function test_sign_flipped_waveforms_normalize_to_same_shape(testCase)
    b_pos.gx.waveform = [0, 5, 10, 5, 0];
    b_neg.gx.waveform = -b_pos.gx.waveform;

    [b0_pos, scales_pos] = pulseg.normalize_block(b_pos);
    [b0_neg, scales_neg] = pulseg.normalize_block(b_neg);

    verifyEqual(testCase, scales_pos.grad(1), 10, 'AbsTol', 1e-10);
    verifyEqual(testCase, scales_neg.grad(1), -10, 'AbsTol', 1e-10);

    verifyEqual(testCase, b0_pos.gx.waveform, b0_neg.gx.waveform, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0_pos.gx.waveform, [0, 0.5, 1, 0.5, 0], 'AbsTol', 1e-10);
end


function test_waveform_first_last_normalized(testCase)
    % first/last are edge values at raster edges and should be normalized
    % by the same signed scale as the waveform.
    b.gx.waveform = [2, 4, 8, 4, 2];
    b.gx.first = 1;
    b.gx.last = -3;

    [b0, scales] = pulseg.normalize_block(b);

    verifyEqual(testCase, scales.grad(1), 8, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.gx.waveform, b.gx.waveform / 8, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.gx.first, 1/8, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.gx.last, -3/8, 'AbsTol', 1e-10);
end


function test_sign_flipped_waveform_first_last_same_normalized_shape(testCase)
    b_pos.gx.waveform = [2, 4, 8, 4, 2];
    b_pos.gx.first = 1;
    b_pos.gx.last = -3;

    b_neg.gx.waveform = -b_pos.gx.waveform;
    b_neg.gx.first = -b_pos.gx.first;
    b_neg.gx.last = -b_pos.gx.last;

    [b0_pos, scales_pos] = pulseg.normalize_block(b_pos);
    [b0_neg, scales_neg] = pulseg.normalize_block(b_neg);

    verifyEqual(testCase, scales_pos.grad(1), 8, 'AbsTol', 1e-10);
    verifyEqual(testCase, scales_neg.grad(1), -8, 'AbsTol', 1e-10);

    verifyEqual(testCase, b0_pos.gx.waveform, b0_neg.gx.waveform, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0_pos.gx.first, b0_neg.gx.first, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0_pos.gx.last, b0_neg.gx.last, 'AbsTol', 1e-10);
end

%% ------------------------------------------------------------------------
%  Gradient - scalar amplitude tests with signed scaling
%% ------------------------------------------------------------------------

function test_gx_amplitude_negative_uses_signed_scale(testCase)
    b.gx.amplitude = -8;

    [b0, scales] = pulseg.normalize_block(b);

    verifyEqual(testCase, scales.grad(1), -8, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.gx.amplitude, 1, 'AbsTol', 1e-10);
end


function test_gy_amplitude_positive(testCase)
    b.gy.amplitude = 5;

    [b0, scales] = pulseg.normalize_block(b);

    verifyEqual(testCase, scales.grad(2), 5, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.gy.amplitude, 1, 'AbsTol', 1e-10);
end


function test_sign_flipped_scalar_amplitudes_normalize_to_same_shape(testCase)
    b_pos.gx.amplitude = 12;
    b_neg.gx.amplitude = -12;

    [b0_pos, scales_pos] = pulseg.normalize_block(b_pos);
    [b0_neg, scales_neg] = pulseg.normalize_block(b_neg);

    verifyEqual(testCase, scales_pos.grad(1), 12, 'AbsTol', 1e-10);
    verifyEqual(testCase, scales_neg.grad(1), -12, 'AbsTol', 1e-10);

    verifyEqual(testCase, b0_pos.gx.amplitude, 1, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0_neg.gx.amplitude, 1, 'AbsTol', 1e-10);
end


function test_grad_amplitude_zero_no_division(testCase)
    b.gz.amplitude = 0;

    [b0, scales] = pulseg.normalize_block(b);

    verifyEqual(testCase, scales.grad(3), 0, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.gz.amplitude, 0, 'AbsTol', 1e-10);
end


function test_amplitude_associated_fields_normalized(testCase)
    % Trapezoid-like gradients often carry area/flatArea/first/last fields.
    % These should be scaled consistently with the signed amplitude so that
    % sign-flipped trapezoids can share a base block.
    b.gx.amplitude = -8;
    b.gx.area = -16;
    b.gx.flatArea = -12;
    b.gx.first = -1;
    b.gx.last = -2;

    [b0, scales] = pulseg.normalize_block(b);

    verifyEqual(testCase, scales.grad(1), -8, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.gx.amplitude, 1, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.gx.area, 2, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.gx.flatArea, 1.5, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.gx.first, 1/8, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.gx.last, 2/8, 'AbsTol', 1e-10);
end

%% ------------------------------------------------------------------------
%  Default / missing gradient fields
%% ------------------------------------------------------------------------

function test_missing_grad_fields_default_zero(testCase)
    b = make_empty_block();

    [~, scales] = pulseg.normalize_block(b);

    verifyEqual(testCase, scales.grad, [0, 0, 0], 'AbsTol', 1e-10);
end


function test_empty_grad_field_ignored(testCase)
    b.gx = [];

    [~, scales] = pulseg.normalize_block(b);

    verifyEqual(testCase, scales.grad(1), 0, 'AbsTol', 1e-10);
end

%% ------------------------------------------------------------------------
%  Input immutability
%% ------------------------------------------------------------------------

function test_original_block_not_mutated(testCase)
    b.rf.signal = [2, 4, 8];
    b.rf.phaseOffset = pi/7;
    b.rf.freqOffset = 99;

    b.gx.waveform = [10, -20, 5];
    b.gx.first = 10;
    b.gx.last = 5;

    b.adc.phaseOffset = pi/5;
    b.adc.freqOffset = -101;

    original = b;

    pulseg.normalize_block(b);

    verifyEqual(testCase, b, original);
end

%% ------------------------------------------------------------------------
%  Combined RF + all gradients + ADC
%% ------------------------------------------------------------------------

function test_full_block_all_fields(testCase)
    b.rf.signal = [0, 3, -6];
    b.rf.phaseOffset = pi/2;
    b.rf.freqOffset = 111;

    b.gx.waveform = [4, 0, -4];   % first abs peak is +4
    b.gx.first = 2;
    b.gx.last = -2;

    b.gy.amplitude = -10;
    b.gy.area = -20;
    b.gy.flatArea = -15;

    b.gz.waveform = [1, 2, 3];

    b.adc.numSamples = 32;
    b.adc.dwell = 8e-6;
    b.adc.phaseOffset = pi/8;
    b.adc.freqOffset = -222;

    [b0, scales] = pulseg.normalize_block(b);

    % RF
    verifyEqual(testCase, scales.rf, 6, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.rf.signal, b.rf.signal / 6, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.rf.phaseOffset, 0, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.rf.freqOffset, 0, 'AbsTol', 1e-10);

    % gx waveform
    verifyEqual(testCase, scales.grad(1), 4, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.gx.waveform, [1, 0, -1], 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.gx.first, 0.5, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.gx.last, -0.5, 'AbsTol', 1e-10);

    % gy amplitude, signed negative
    verifyEqual(testCase, scales.grad(2), -10, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.gy.amplitude, 1, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.gy.area, 2, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.gy.flatArea, 1.5, 'AbsTol', 1e-10);

    % gz waveform
    verifyEqual(testCase, scales.grad(3), 3, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.gz.waveform, [1/3, 2/3, 1], 'AbsTol', 1e-10);

    % ADC copied except dynamic offsets zeroed
    verifyEqual(testCase, b0.adc.numSamples, b.adc.numSamples);
    verifyEqual(testCase, b0.adc.dwell, b.adc.dwell, 'AbsTol', 1e-12);
    verifyEqual(testCase, b0.adc.phaseOffset, 0, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.adc.freqOffset, 0, 'AbsTol', 1e-10);
end
