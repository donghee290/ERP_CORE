function AlphaEyesOpenClosed
% ALPHA EYES OPEN / CLOSED EXPERIMENT
%
% Purpose:
%   Compare alpha activity between eyes-closed and eyes-open conditions.
%
% Procedure:
%   Low beep  (0.5 s) -> Eyes Open (~10 s)
%   High beep (0.5 s) -> Eyes Closed   (~10 s)
%   Repeat for 3 cycles.
%
% Duration:
%   Approximately 1 minute.
%
% Jitter:
%   Eyes Open / Closed duration randomly varies from 9 to 11 s.
%
% Trigger:
%   1 = Low beep START
%   4 = Low beep END
%   16 = High beep START
%   64 = High beep END


%% Experiment settings
fs = 44100;
duration = 0.5;

lowFreq = 300;
highFreq = 800;

nCycles = 3;

% Duration jitter: 9.5 ~ 10.5 s
jitterMin = 9;
jitterMax = 11;

% BioSemi trigger codes
lowStartTrigger  = 3;    % 00000001
lowEndTrigger    = 7;    % 00000100
highStartTrigger = 19;   % 00010000
highEndTrigger   = 67;   % 01000000

rng('shuffle');


%% Initialize Psychtoolbox
PsychDefaultSetup(1);
KbName('UnifyKeyNames');

escapeKey = KbName('ESCAPE');

screenNumber = max(Screen('Screens'));
win = [];
sp = [];


%% Create beep sounds
t = 0:1/fs:duration-1/fs;

lowBeep = sin(2*pi*lowFreq*t);
highBeep = sin(2*pi*highFreq*t);


try
    %% Screen
    [win, winRect] = PsychImaging('OpenWindow', ...
        screenNumber, [128 128 128]);

    [xCenter, yCenter] = RectCenter(winRect);

    Screen('TextFont', win, 'Arial');
    Screen('TextSize', win, 72);
    Screen('TextStyle', win, 0);

    HideCursor;
    ListenChar(2);

    %% Connect BioSemi trigger interface
    sp = openBioSemiTrigger();

    fprintf('Alpha experiment started.\n');


    %% Experiment
    for cycle = 1:nCycles

        %% Low beep -> Eyes Open
        Screen('FillRect', win, [128 128 128]);
    
        DrawFormattedText(win, ...
            'Open your eyes', ...
            'center', 'center', [255 255 255]);
    
        Screen('Flip', win);
    
        sendBioSemiTrigger(sp, lowStartTrigger);   % Low beep START
        sound(lowBeep, fs);
    
        waitWithEscape(duration, escapeKey);
    
        sendBioSemiTrigger(sp, lowEndTrigger);     % Low beep END
    
        % Apply jitter to Eyes Closed duration
        closedDuration = jitterMin + ...
            (jitterMax - jitterMin) * rand;
    
        fprintf('Cycle %d | Eyes Open | %.3f s\n', ...
            cycle, closedDuration);
    
        waitWithEscape(closedDuration, escapeKey);
    
    
        %% High beep -> Eyes Closed
        Screen('FillRect', win, [128 128 128]);
    
        DrawFormattedText(win, ...
            'Close your eyes', ...
            'center', 'center', [255 255 255]);
    
        Screen('Flip', win);
    
        sendBioSemiTrigger(sp, highStartTrigger);  % High beep START
        sound(highBeep, fs);
    
        waitWithEscape(duration, escapeKey);
    
        sendBioSemiTrigger(sp, highEndTrigger);    % High beep END
    
        % Apply jitter to Eyes Open duration
        openDuration = jitterMin + ...
            (jitterMax - jitterMin) * rand;
    
        fprintf('Cycle %d | Eyes Closed | %.3f s\n', ...
            cycle, openDuration);
    
        waitWithEscape(openDuration, escapeKey);

    end


    %% End
    fprintf('Experiment complete.\n');

    closeExperiment(win, sp);

catch ME

    closeExperiment(win, sp);

    if strcmp(ME.message, 'USER_ABORT')
        fprintf('\nExperiment aborted.\n');
    else
        rethrow(ME);
    end

end


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


function waitWithEscape(waitTime, escapeKey)

    startTime = GetSecs;

    while GetSecs - startTime < waitTime

        [keyDown, ~, keyCode] = KbCheck;

        if keyDown && keyCode(escapeKey)
            error('USER_ABORT');
        end

        WaitSecs('YieldSecs', 0.01);
    end
end


function closeExperiment(win, sp)

    if ~isempty(sp)
        clear sp;
    end

    ListenChar(0);
    ShowCursor;

    if ~isempty(win)
        Screen('CloseAll');
    end

end