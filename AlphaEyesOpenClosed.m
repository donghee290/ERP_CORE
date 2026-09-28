function AlphaEyesOpenClosed
% ALPHA EYES OPEN / CLOSED EXPERIMENT
%
% Purpose:
%   Compare alpha activity between eyes-closed and eyes-open conditions.
%
% Procedure:
%   Low beep  (0.5 s) -> Eyes Closed (~10 s)
%   High beep (0.5 s) -> Eyes Open   (~10 s)
%   Repeat for 3 cycles.
%
% Duration:
%   Approximately 1 minute.
%
% Jitter:
%   Eyes Closed / Open duration randomly varies from 9.5 to 10.5 s.
%
% Trigger:
%   1 = Low beep START
%   2 = Low beep END
%   4 = High beep START
%   8 = High beep END


%% Experiment settings
fs = 44100;
duration = 0.5;

lowFreq = 400;
highFreq = 800;

nCycles = 3;

% Duration jitter: 9.5 ~ 10.5 s
jitterMin = 9.5;
jitterMax = 10.5;

% BioSemi trigger codes
lowStartTrigger  = 1;    % 00000001
lowEndTrigger    = 4;    % 00000100
highStartTrigger = 16;   % 00010000
highEndTrigger   = 64;   % 01000000

rng('shuffle');


%% Create beep sounds
t = 0:1/fs:duration-1/fs;

lowBeep = sin(2*pi*lowFreq*t);
highBeep = sin(2*pi*highFreq*t);


%% Connect BioSemi trigger interface
sp = openBioSemiTrigger();

fprintf('Alpha experiment started.\n');


%% Experiment
for cycle = 1:nCycles

    %% Low beep -> Eyes Closed
    sendBioSemiTrigger(sp, lowStartTrigger);   % Low beep START
    sound(lowBeep, fs);

    WaitSecs(duration);

    sendBioSemiTrigger(sp, lowEndTrigger);     % Low beep END

    % Apply jitter to Eyes Closed duration
    closedDuration = jitterMin + ...
        (jitterMax - jitterMin) * rand;

    fprintf('Cycle %d | Eyes Closed | %.3f s\n', ...
        cycle, closedDuration);

    WaitSecs(closedDuration);


    %% High beep -> Eyes Open
    sendBioSemiTrigger(sp, highStartTrigger);  % High beep START
    sound(highBeep, fs);

    WaitSecs(duration);

    sendBioSemiTrigger(sp, highEndTrigger);    % High beep END

    % Apply jitter to Eyes Open duration
    openDuration = jitterMin + ...
        (jitterMax - jitterMin) * rand;

    fprintf('Cycle %d | Eyes Open | %.3f s\n', ...
        cycle, openDuration);

    WaitSecs(openDuration);

end


%% End
fprintf('Alpha experiment complete.\n');

clear sp;

end


%% BioSemi USB Trigger Interface
function sp = openBioSemiTrigger()
% Connect to BioSemi USB trigger interface using the Linux serial port.

    portName = "/dev/ttyUSB0";

    ports = serialportlist("available");

    if ~any(strcmpi(ports, portName))
        error('BioSemi trigger cable not found on %s.', portName);
    end

    sp = serialport(portName, 115200, ...
        "DataBits", 8, ...
        "StopBits", 1);

    fprintf('BioSemi trigger connected: %s\n', portName);

end


function sendBioSemiTrigger(sp, code)
% Send an 8-bit trigger code (1-255) to BioSemi.

    if code < 1 || code > 255
        error('Trigger code must be between 1 and 255.');
    end

    write(sp, uint8(code), "uint8");

end