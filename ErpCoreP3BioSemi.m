function ErpCoreP3BioSemi
% ERP CORE Active Visual Oddball P3
% MATLAB + Psychtoolbox + BioSemi USB Trigger Interface
%
% Stimuli: A-E
% 5 blocks x 40 trials
% Each letter: 20% per block
% Stimulus: 200 ms
% ISI(Inter-Stimulus Interval): 1200-1400 ms
%
% Trigger:
%   A = 1      (00000001)
%   B = 2      (00000010)
%   C = 4      (00000100)
%   D = 8      (00001000)
%   E = 16     (00010000)
%   Target flag = 32
%
%   Target stimulus = stimulus code + 32
%   e.g. target C -> 4 + 32 = 36 (00100100)
%
% Response:
%   LeftArrow  = target
%   RightArrow = non-target
%   correct    -> trigger 64
%   incorrect  -> trigger 128
%   ESC        -> abort


%% Experiment settings
letters = {'A','B','C','D','E'};
stimCodes = [1 2 4 8 16];
targetFlag = 32;
correctCode = 64;
incorrectCode = 128;

nBlocks = 5;
trialsPerBlock = 40;

stimDuration = 0.200;
isiMin = 1.200;
isiMax = 1.400;

%% Initialize Psychtoolbox
rng('shuffle');
PsychDefaultSetup(1);
KbName('UnifyKeyNames');

targetKey = KbName('LeftArrow');
nonTargetKey = KbName('RightArrow');
escapeKey = KbName('ESCAPE');
startKey = KbName('space');

keys = zeros(1,256);
keys([targetKey nonTargetKey escapeKey]) = 1;

screenNumber = max(Screen('Screens'));
win = [];
sp = [];

try
    % Screen
    [win, winRect] = PsychImaging('OpenWindow', screenNumber, [128 128 128]);
    ifi = Screen('GetFlipInterval', win);
    [xCenter, yCenter] = RectCenter(winRect);

    Screen('TextFont', win, 'Arial');
    Screen('TextSize', win, 72);
    HideCursor;
    ListenChar(2);

    % BioSemi USB Trigger Interface (/dev/ttyUSB0)
    sp = openBioSemiTrigger();

    % Keyboard queue
    KbQueueCreate([], keys);
    KbQueueStart();

    % Each block contains each letter exactly 8 times.
    baseSequence = repelem(1:5, trialsPerBlock / 5);

    % Each letter becomes the target once.
    targetOrder = randperm(5);

    %% Start

    Screen('TextSize', win, 72);
    Screen('TextStyle', win, 0);

    DrawFormattedText(win, ...
        'ERP CORE VISUAL ODDBALL', ...
        'center', yCenter - 80, [255 255 255]);

    Screen('TextSize', win, 48);

    DrawFormattedText(win, ...
        'Press SPACE to start.', ...
        'center', yCenter + 60, [255 255 255]);

    Screen('Flip', win);
    waitForKey(startKey, escapeKey);

    %% Task
    for block = 1:nBlocks

        targetIdx = targetOrder(block);
        targetLetter = letters{targetIdx};
        blockSequence = baseSequence(randperm(trialsPerBlock));

        % Explanation
        Screen('TextSize', win, 72);
        Screen('TextStyle', win, 0);
        DrawFormattedText(win, ...
            sprintf('Block %d / %d', block, nBlocks), ...
            'center', yCenter - 220, [255 255 255]);

        prefix = 'TARGET = ';

        Screen('TextSize', win, 72);
        Screen('TextStyle', win, 0);
        prefixBounds = Screen('TextBounds', win, prefix);
        prefixWidth = RectWidth(prefixBounds);

        Screen('TextStyle', win, 1); % bold
        targetBounds = Screen('TextBounds', win, targetLetter);
        targetWidth = RectWidth(targetBounds);

        startX = xCenter - (prefixWidth + targetWidth) / 2;

        Screen('TextStyle', win, 0);
        Screen('DrawText', win, prefix, startX, yCenter - 100, [255 255 255]);

        Screen('TextStyle', win, 1); % bold
        Screen('DrawText', win, targetLetter, ...
            startX + prefixWidth, yCenter - 100, [255 255 255]);

        Screen('TextStyle', win, 0); % reset


        Screen('TextSize', win, 32);
        DrawFormattedText(win, ...
            'LEFT ARROW(←)  = TARGET', ...
            'center', yCenter + 30, [255 255 255]);

        DrawFormattedText(win, ...
            'RIGHT ARROW(→) = NON-TARGET', ...
            'center', yCenter + 75, [255 255 255]);


        Screen('TextSize', win, 48);
        DrawFormattedText(win, ...
            'Press SPACE to begin.', ...
            'center', yCenter + 180, [255 255 255]);


        Screen('Flip', win);
        waitForKey(startKey, escapeKey);

        % Fixation before the first stimulus.
        drawFixation(win, xCenter, yCenter);
        fixationOnset = Screen('Flip', win);
        nextStimOnset = fixationOnset + randomISI(isiMin, isiMax);

        for trial = 1:trialsPerBlock

            stimIdx = blockSequence(trial);
            stimLetter = letters{stimIdx};
            isTarget = (stimIdx == targetIdx);

            % Bit-based stimulus trigger code.
            stimCode = stimCodes(stimIdx);

            if isTarget
                stimCode = stimCode + targetFlag;
            end

            % Ignore keys pressed before this trial.
            KbQueueFlush();

            %% Stimulus ON
            Screen('FillRect', win, [128 128 128]);
            DrawFormattedText(win, stimLetter, ...
                'center', 'center', [0 0 0]);
            drawFixation(win, xCenter, yCenter);

            stimOnset = Screen('Flip', win, nextStimOnset - 0.5 * ifi);

            sendBioSemiTrigger(sp, stimCode);

            fprintf('STIM | Block %d Trial %02d | Target=%s Stim=%s | Trigger=%d\n', ...
                block, trial, targetLetter, stimLetter, stimCode);

            %% Prepare fixation screen
            Screen('FillRect', win, [128 128 128]);
            drawFixation(win, xCenter, yCenter);

            stimOffsetTime = stimOnset + stimDuration;
            isi = randomISI(isiMin, isiMax);
            nextStimOnset = stimOffsetTime + isi;

            responded = false;
            stimOff = false;

            %% Response + timing loop
            while GetSecs < nextStimOnset - 0.5 * ifi

                now = GetSecs;

                % Remove the letter after 200 ms.
                if ~stimOff && now >= stimOffsetTime - ifi
                    Screen('Flip', win, stimOffsetTime - 0.5 * ifi);
                    stimOff = true;
                end

                % Check keyboard response.
                if ~responded
                    [pressed, firstPress] = KbQueueCheck();

                    if pressed
                        if firstPress(escapeKey) > 0
                            error('USER_ABORT');
                        elseif firstPress(targetKey) > 0
                            responseIsTarget = true;
                            rt = firstPress(targetKey) - stimOnset;
                            responded = true;
                        elseif firstPress(nonTargetKey) > 0
                            responseIsTarget = false;
                            rt = firstPress(nonTargetKey) - stimOnset;
                            responded = true;
                        end

                        if responded
                            correct = (responseIsTarget == isTarget);

                            if correct
                                responseCode = correctCode;
                            else
                                responseCode = incorrectCode;                            
                            end

                            sendBioSemiTrigger(sp, responseCode);

                            fprintf('RESP | Trigger=%d | Correct=%d | RT=%.3f s\n', ...
                                responseCode, correct, rt);
                        end
                    end
                end

                WaitSecs('YieldSecs', 0.001);
            end
        end

        if block < nBlocks

            % Explanation
            Screen('TextSize', win, 72);
            DrawFormattedText(win, ...
                sprintf('Block %d complete.', block), ...
                'center', yCenter - 60, [255 255 255]);

            Screen('TextSize', win, 48);
            DrawFormattedText(win, ...
                'Press SPACE for the next block.', ...
                'center', yCenter + 60, [255 255 255]);

            Screen('Flip', win);
            waitForKey(startKey, escapeKey);

        end
    end

    %% End
    Screen('TextSize', win, 72);
    DrawFormattedText(win, ...
        'Trigger test complete.', ...
        'center', yCenter - 60, [255 255 255]);

    Screen('TextSize', win, 48);
    DrawFormattedText(win, ...
        'Press SPACE to finish.', ...
        'center', yCenter + 60, [255 255 255]);

    Screen('Flip', win);
    waitForKey(startKey, escapeKey);

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

    if code < 1 || code > 255
        error('Trigger code must be between 1 and 255.');
    end

    write(sp, uint8(code), "uint8");
end


%% Helpers
function isi = randomISI(minISI, maxISI)
    isi = minISI + (maxISI - minISI) * rand;
end


function drawFixation(win, xCenter, yCenter)
    Screen('DrawDots', win, [xCenter; yCenter], ...
        6, [255 255 255], [], 2);
end


function waitForKey(startKey, escapeKey)
    KbReleaseWait;

    while true
        [keyDown, ~, keyCode] = KbCheck;

        if keyDown
            if keyCode(escapeKey)
                error('USER_ABORT');
            elseif keyCode(startKey)
                KbReleaseWait;
                return;
            end
        end

        WaitSecs('YieldSecs', 0.01);
    end
end


function closeExperiment(win, sp)

    try
        KbQueueStop();
        KbQueueRelease();
    catch
    end

    if ~isempty(sp)
        clear sp;
    end

    ListenChar(0);
    ShowCursor;

    if ~isempty(win)
        Screen('CloseAll');
    end
end