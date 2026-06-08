% test_get_grad_scale.m
% Unit tests for get_grad_scale.m
% Run with: results = runtests('test_get_grad_scale'); table(results)

function tests = test_get_grad_scale
    tests = functiontests(localfunctions);
end

%% Trapezoid Tests

function test_trap_positive(testCase)
    g.type = 'trap';
    g.amplitude = 20e3;
    testCase.verifyEqual(pulseg.get_grad_scale(g), 20e3);
end

function test_trap_negative(testCase)
    g.type = 'trap';
    g.amplitude = -20e3;
    testCase.verifyEqual(pulseg.get_grad_scale(g), -20e3);
end

function test_trap_zero(testCase)
    g.type = 'trap';
    g.amplitude = 0;
    testCase.verifyEqual(pulseg.get_grad_scale(g), 0);
end

%% Arbitrary Gradient Tests

function test_grad_positive_peak(testCase)
    g.type = 'grad';
    g.waveform = [-5e3, 10e3, 3e3, -2e3];
    testCase.verifyEqual(pulseg.get_grad_scale(g), 10e3);
end

function test_grad_negative_peak(testCase)
    g.type = 'grad';
    g.waveform = [5e3, -10e3, 3e3, 2e3];
    testCase.verifyEqual(pulseg.get_grad_scale(g), -10e3);
end

function test_grad_equal_magnitude_prefers_positive(testCase)
    g.type = 'grad';
    g.waveform = [-10e3, 10e3, 3e3];
    testCase.verifyEqual(pulseg.get_grad_scale(g), 10e3);
end

function test_grad_all_positive(testCase)
    g.type = 'grad';
    g.waveform = [1e3, 5e3, 3e3];
    testCase.verifyEqual(pulseg.get_grad_scale(g), 5e3);
end

function test_grad_all_negative(testCase)
    g.type = 'grad';
    g.waveform = [-1e3, -5e3, -3e3];
    testCase.verifyEqual(pulseg.get_grad_scale(g), -5e3);
end

function test_grad_single_element(testCase)
    g.type = 'grad';
    g.waveform = [7e3];
    testCase.verifyEqual(pulseg.get_grad_scale(g), 7e3);
end

%% Error Handling Tests

function test_not_a_struct(testCase)
    testCase.verifyError(@() pulseg.get_grad_scale(42), 'get_grad_scale:invalidInput');
end

function test_missing_type_field(testCase)
    g.amplitude = 10e3;
    testCase.verifyError(@() pulseg.get_grad_scale(g), 'get_grad_scale:missingField');
end

function test_invalid_type(testCase)
    g.type = 'unknown';
    testCase.verifyError(@() pulseg.get_grad_scale(g), 'get_grad_scale:unknownType');
end

function test_trap_missing_amplitude(testCase)
    g.type = 'trap';
    testCase.verifyError(@() pulseg.get_grad_scale(g), 'get_grad_scale:missingField');
end

function test_grad_missing_waveform(testCase)
    g.type = 'grad';
    testCase.verifyError(@() pulseg.get_grad_scale(g), 'get_grad_scale:missingField');
end

