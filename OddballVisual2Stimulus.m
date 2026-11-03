function ERPCoreP3BioSemi_2Stimulus
% 2-STIMULUS VISUAL ODDBALL P3
%
% Stimuli:
%   A = Target     (20%)
%   B = Non-target (80%) 
%
% Procedure:
%   2 blocks x 40 trials
%   A: 8 trials per block
%   B: 32 trials per block
%
% Stimulus duration:
%   200 ms
%
% ISI jitter:
%   1200-1400 ms
%
% Response:
%   LeftArrow  = Target
%   RightArrow = Non-target
%
% Trigger:
%   A stimulus = 1   (00000001)
%   LeftArrow  = 4   (00000100)
%   B stimulus = 16  (00010000)
%   RightArrow = 64  (01000000)
%
% Trigger lines are spaced apart for easier visual identification
% in BioSemi ActiView.
%
% ESC = abort


%% Experiment settings

letters = {'A','B'};

targetIdx = 1;      % A
nonTargetIdx = 2;   % B

stimCodes = [1 16];

leftCode  = 4;
rightCode = 64;

nBlocks = 4;
trialsPerBlock = 40;

nTarget = 8;
nNonTarget = 32;

stimDuration = 0.500;

% ISI jitter: fixation duration randomly varies from 1.2 to 1.4 s
isiMin = 1.000;
isiMax = 1.500;


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

    %% Screen

    [win, winRect] = PsychImaging('OpenWindow', ...
        screenNumber, [128 128 128]);

    ifi = Screen('GetFlipInterval', win);
    [xCenter, yCenter] = RectCenter(winRect);

    Screen('TextFont', win, 'Arial');

    HideCursor;
    ListenChar(2);


    %% BioSemi USB Trigger Interface

    sp = openBioSemiTrigger();


    %% Keyboard queue

    KbQueueCreate([], keys);
    KbQueueStart();


    %% Start screen

    Screen('TextSize', win, 72);
    Screen('TextStyle', win, 0);

    DrawFormattedText(win, ...
        '2-STIMULUS VISUAL ODDBALL', ...
        'center', yCenter - 80, [255 255 255]);

    Screen('TextSize', win, 48);

    DrawFormattedText(win, ...
        'Press SPACE to start.', ...
        'center', yCenter + 60, [255 255 255]);

    Screen('Flip', win);

    waitForKey(startKey, escapeKey);


    %% Experiment

    for block = 1:nBlocks

        % A = 8 trials, B = 32 trials
        blockSequence = [ ...
            repmat(targetIdx, 1, nTarget), ...
            repmat(nonTargetIdx, 1, nNonTarget)];

        % Randomize trial order
        blockSequence = blockSequence(randperm(trialsPerBlock));


        %% Block instruction

        Screen('TextSize', win, 72);
        Screen('TextStyle', win, 0);

        DrawFormattedText(win, ...
            sprintf('Block %d / %d', block, nBlocks), ...
            'center', yCenter - 220, [255 255 255]);


        % TARGET = A
        prefix = 'TARGET = ';

        prefixBounds = Screen('TextBounds', win, prefix);
        prefixWidth = RectWidth(prefixBounds);

        Screen('TextStyle', win, 1);

        targetBounds = Screen('TextBounds', win, 'A');
        targetWidth = RectWidth(targetBounds);

        startX = xCenter - (prefixWidth + targetWidth) / 2;

        Screen('TextStyle', win, 0);

        Screen('DrawText', win, ...
            prefix, startX, yCenter - 100, [255 255 255]);

        Screen('TextStyle', win, 1);

        Screen('DrawText', win, ...
            'A', startX + prefixWidth, ...
            yCenter - 100, [255 255 255]);

        Screen('TextStyle', win, 0);


        Screen('TextSize', win, 32);

        DrawFormattedText(win, ...
            'LEFT ARROW(←) = TARGET', ...
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


        %% Fixation before first stimulus

        drawFixation(win, xCenter, yCenter);

        fixationOnset = Screen('Flip', win);

        nextStimOnset = fixationOnset + ...
            randomISI(isiMin, isiMax);


        %% Trials

        for trial = 1:trialsPerBlock

            stimIdx = blockSequence(trial);

            stimLetter = letters{stimIdx};

            isTarget = (stimIdx == targetIdx);

            stimCode = stimCodes(stimIdx);


            % Ignore responses before this trial
            KbQueueFlush();


            %% Stimulus ON

            Screen('FillRect', win, [128 128 128]);

            Screen('TextSize', win, 100);
            Screen('TextStyle', win, 0);

            DrawFormattedText(win, ...
                stimLetter, ...
                'center', 'center', [0 0 0]);

            drawFixation(win, xCenter, yCenter);

            stimOnset = Screen('Flip', win, ...
                nextStimOnset - 0.5 * ifi);

            sendBioSemiTrigger(sp, stimCode);

            fprintf( ...
                'STIM | Block %d Trial %02d | Stim=%s | Trigger=%d\n', ...
                block, trial, stimLetter, stimCode);


            %% Prepare fixation screen

            Screen('FillRect', win, [128 128 128]);

            drawFixation(win, xCenter, yCenter);

            stimOffsetTime = stimOnset + stimDuration;


            % Apply ISI jitter for next stimulus
            isi = randomISI(isiMin, isiMax);

            nextStimOnset = stimOffsetTime + isi;


            responded = false;
            stimOff = false;


            %% Response + timing loop

            while GetSecs < nextStimOnset - 0.5 * ifi

                now = GetSecs;


                % Remove stimulus after 200 ms
                if ~stimOff && now >= stimOffsetTime - ifi

                    Screen('Flip', win, ...
                        stimOffsetTime - 0.5 * ifi);

                    stimOff = true;

                end


                %% Check keyboard response

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

                            correct = ...
                                (responseIsTarget == isTarget);


                            if responseIsTarget

                                responseCode = leftCode;

                            else

                                responseCode = rightCode;

                            end


                            sendBioSemiTrigger( ...
                                sp, responseCode);


                            fprintf( ...
                                ['RESP | Trigger=%d | ' ...
                                 'Correct=%d | RT=%.3f s\n'], ...
                                responseCode, correct, rt);

                        end

                    end

                end


                WaitSecs('YieldSecs', 0.001);

            end

        end


        %% End of block

        if block < nBlocks

            Screen('TextSize', win, 72);

            DrawFormattedText(win, ...
                sprintf('Block %d complete.', block), ...
                'center', yCenter - 60, ...
                [255 255 255]);


            Screen('TextSize', win, 48);

            DrawFormattedText(win, ...
                'Press SPACE for the next block.', ...
                'center', yCenter + 60, ...
                [255 255 255]);


            Screen('Flip', win);

            waitForKey(startKey, escapeKey);

        end

    end


    %% End screen

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

        error( ...
            'BioSemi trigger cable not found on %s.', ...
            portName);

    end

    sp = serialport( ...
        portName, 115200, ...
        "DataBits", 8, ...
        "StopBits", 1);

    fprintf( ...
        'BioSemi trigger connected: %s\n', ...
        portName);

end


function sendBioSemiTrigger(sp, code)

    if code < 1 || code > 255

        error( ...
            'Trigger code must be between 1 and 255.');

    end

    write(sp, uint8(code), "uint8");

end


%% Helpers

function isi = randomISI(minISI, maxISI)

    isi = minISI + ...
        (maxISI - minISI) * rand;

end


function drawFixation(win, xCenter, yCenter)

    Screen('DrawDots', ...
        win, ...
        [xCenter; yCenter], ...
        6, ...
        [255 255 255], ...
        [], ...
        2);

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