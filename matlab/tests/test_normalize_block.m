function tests = test_normalize_block
    % Return a test suite using the function-based unit testing framework
    tests = functiontests(localfunctions);
end

%% ─────────────────────────────────────────────
%  Helper
%% ─────────────────────────────────────────────
function b = make_empty_block()
    b = struct();
end

%% ─────────────────────────────────────────────
%  RF tests
%% ─────────────────────────────────────────────
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
    % All-zero signal — should not divide; output equals input
    b.rf.signal = [0, 0, 0];
    [b0, scales] = pulseg.normalize_block(b);

    verifyEqual(testCase, scales.rf, 0, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.rf.signal, [0, 0, 0], 'AbsTol', 1e-10);
end

function test_rf_complex_signal(testCase)
    b.rf.signal = [3+4i, -1+0i];   % max |·| = 5
    [b0, scales] = pulseg.normalize_block(b);

    verifyEqual(testCase, scales.rf, 5, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.rf.signal, b.rf.signal / 5, 'AbsTol', 1e-10);
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

%% ─────────────────────────────────────────────
%  Gradient – waveform tests
%% ─────────────────────────────────────────────
function test_gx_waveform_normalizes(testCase)
    b.gx.waveform = [10, -20, 5];
    [b0, scales] = pulseg.normalize_block(b);

    verifyEqual(testCase, scales.grad(1), 20, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.gx.waveform, [0.5, -1, 0.25], 'AbsTol', 1e-10);
end

function test_gy_waveform_normalizes(testCase)
    b.gy.waveform = [-3, 0, 3];
    [b0, scales] = pulseg.normalize_block(b);

    verifyEqual(testCase, scales.grad(2), 3, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.gy.waveform, [-1, 0, 1], 'AbsTol', 1e-10);
end

function test_gz_waveform_normalizes(testCase)
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

%% ─────────────────────────────────────────────
%  Gradient – amplitude tests
%% ─────────────────────────────────────────────
function test_gx_amplitude_normalizes(testCase)
    b.gx.amplitude = -8;
    [b0, scales] = pulseg.normalize_block(b);

    verifyEqual(testCase, scales.grad(1), 8, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.gx.amplitude, -1, 'AbsTol', 1e-10);
end

function test_gy_amplitude_positive(testCase)
    b.gy.amplitude = 5;
    [b0, scales] = pulseg.normalize_block(b);

    verifyEqual(testCase, scales.grad(2), 5, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.gy.amplitude, 1, 'AbsTol', 1e-10);
end

function test_grad_amplitude_zero_no_division(testCase)
    b.gz.amplitude = 0;
    [b0, scales] = pulseg.normalize_block(b);

    verifyEqual(testCase, scales.grad(3), 0, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.gz.amplitude, 0, 'AbsTol', 1e-10);
end

%% ─────────────────────────────────────────────
%  Default / missing gradient fields
%% ─────────────────────────────────────────────
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

%% ─────────────────────────────────────────────
%  Input immutability
%% ─────────────────────────────────────────────
function test_original_block_not_mutated(testCase)
    b.rf.signal  = [2, 4, 8];
    b.gx.waveform = [10, 20];
    original_rf  = b.rf.signal;
    original_gx  = b.gx.waveform;

    pulseg.normalize_block(b);

    verifyEqual(testCase, b.rf.signal,   original_rf, 'AbsTol', 1e-10);
    verifyEqual(testCase, b.gx.waveform, original_gx, 'AbsTol', 1e-10);
end

%% ─────────────────────────────────────────────
%  Combined RF + all gradients
%% ─────────────────────────────────────────────
function test_full_block_all_fields(testCase)
    b.rf.signal   = [0, 3, -6];
    b.gx.waveform = [4, 0, -4];
    b.gy.amplitude = 10;
    b.gz.waveform = [1, 2, 3];

    [b0, scales] = pulseg.normalize_block(b);

    % RF
    verifyEqual(testCase, scales.rf,      6,  'AbsTol', 1e-10);
    verifyEqual(testCase, b0.rf.signal,   b.rf.signal / 6, 'AbsTol', 1e-10);

    % gx (waveform)
    verifyEqual(testCase, scales.grad(1), 4,  'AbsTol', 1e-10);
    verifyEqual(testCase, b0.gx.waveform, [1, 0, -1], 'AbsTol', 1e-10);

    % gy (amplitude)
    verifyEqual(testCase, scales.grad(2), 10, 'AbsTol', 1e-10);
    verifyEqual(testCase, b0.gy.amplitude, 1, 'AbsTol', 1e-10);

    % gz (waveform)
    verifyEqual(testCase, scales.grad(3), 3,  'AbsTol', 1e-10);
    verifyEqual(testCase, b0.gz.waveform, [1/3, 2/3, 1], 'AbsTol', 1e-10);
end
