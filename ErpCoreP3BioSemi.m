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
%   tens digit = target letter
%   ones digit = presented letter
%   A=1, B=2, C=3, D=4, E=5
%   e.g. target B + stimulus C -> 23
%   target trials -> 11, 22, 33, 44, 55
%
% Response:
%   LeftArrow  = target
%   RightArrow = non-target
%   correct    -> trigger 201
%   incorrect  -> trigger 202
%   ESC        -> abort

%% Experiment settings
letters = {'A','B','C','D','E'};
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

    % BioSemi USB Trigger Interface (COM3)
    sp = openBioSemiTrigger();

    % Keyboard queue
    KbQueueCreate([], keys);
    KbQueueStart();

    % Each block contains each letter exactly 8 times.
    baseSequence = repelem(1:5, trialsPerBlock / 5);

    % Each letter becomes the target once.
    targetOrder = randperm(5);

    %% Start
    DrawFormattedText(win, ...
        ['ERP CORE VISUAL ODDBALL\n\n' ...
         'LEFT ARROW  = TARGET\n' ...
         'RIGHT ARROW = NON-TARGET\n\n' ...
         'Press SPACE to start.'], ...
        'center', 'center', [255 255 255]);
    Screen('Flip', win);
    waitForKey(startKey, escapeKey);

    %% Task
    for block = 1:nBlocks

        targetIdx = targetOrder(block);
        targetLetter = letters{targetIdx};
        blockSequence = baseSequence(randperm(trialsPerBlock));

        DrawFormattedText(win, ...
            sprintf(['Block %d / %d\n\n' ...
                     'TARGET = %s\n\n' ...
                     'LEFT ARROW  = TARGET\n' ...
                     'RIGHT ARROW = NON-TARGET\n\n' ...
                     'Press SPACE to begin.'], ...
                     block, nBlocks, targetLetter), ...
            'center', 'center', [255 255 255]);
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

            % ERP CORE stimulus event code.
            stimCode = 10 * targetIdx + stimIdx;

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
                                responseCode = 201;
                            else
                                responseCode = 202;
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
            DrawFormattedText(win, ...
                sprintf('Block %d complete.\n\nPress SPACE for the next block.', block), ...
                'center', 'center', [255 255 255]);
            Screen('Flip', win);
            waitForKey(startKey, escapeKey);
        end
    end

    %% End
    DrawFormattedText(win, ...
        'Trigger test complete.\n\nPress SPACE to finish.', ...
        'center', 'center', [255 255 255]);
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

    instrreset;

    serialInfo = instrhwinfo('serial');
    availablePorts = serialInfo.AvailableSerialPorts;

    if ~any(strcmp(availablePorts, 'COM3'))
        error('BioSemi trigger cable not found on COM3.');
    end

    sp = serial('COM3', ...
        'BaudRate', 115200, ...
        'DataBits', 8, ...
        'StopBits', 1);

    fopen(sp);

    fprintf('BioSemi trigger connected: %s\n', sp.Port);
end


function sendBioSemiTrigger(sp, code)

    if code < 1 || code > 255
        error('Trigger code must be between 1 and 255.');
    end

    fwrite(sp, uint8(code));
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
        try
            if strcmpi(sp.Status, 'open')
                fclose(sp);
            end
            delete(sp);
        catch
        end
    end

    ListenChar(0);
    ShowCursor;

    if ~isempty(win)
        Screen('CloseAll');
    end
end