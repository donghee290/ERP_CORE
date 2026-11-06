function TPMAttention(participantID)
%% TPM_BioSemi - Tagged Priority-Map (core task, no frequency tagging)
% MATLAB + Psychtoolbox + BioSemi USB trigger interface.
%
% Example:
%    TPMAttention('P001')
%
% Based on the supplied TPM proposal.
% 2 sessions x 10 blocks x 90 trials = 1800 trials.
%
% Eye tracking, photodiode, and RIFT are NOT implemented.
%
% IMPORTANT: Check actual stimulus size, RGB/gamut, trigger recording and
% timing on the laboratory equipment BEFORE collecting EEG data.
%
% Cue-display SOA is measured from cue onset.
% RT window is 1500ms from actual search-display onset.
% Display remains visible for 200ms even when response is early.
% After the response window ends OR the first response is received and
% display has offset, the next trial's 600-900 ms fixation starts.
% No additional ITI or trial-by-trial feedback.

if nargin < 1 || isempty(participantID)
    participantID = input('Participant ID: ', 's');
end
participantID = char(participantID);
assert(~isempty(regexp(participantID, '^[A-Za-z0-9_-]+$', 'once')), ...
    'Participant ID: use letters, digits, _ or - only.');

%% Configuration
cfg.portName         = '/dev/ttyUSB0';
cfg.useTriggers      = false;  % set false for coding/offline debug only

cfg.screenNumber     = max(Screen('Screens'));
cfg.viewDistanceMM   = 600;   % 60 cm
cfg.screenWidthMM    = NaN;   % use Screen('DisplaySize'); optionally override after measurement

cfg.bg               = [128 128 128];
cfg.fixColor         = [255 255 255];
cfg.ringColor        = [225 225 225];
cfg.lineColor        = [25 25 25];

cfg.radiusDeg        = 4.0;
cfg.shapeDiameterDeg = 0.80;  % provisional
cfg.ringDiameterDeg  = 1.10;  % provisional
cfg.lineLengthDeg    = 0.45;  % provisional

cfg.lineWidthPx      = 2;
cfg.ringWidthPx      = 2;
cfg.fixDiameterPx    = 6;
cfg.instructionPx    = 26;

cfg.fixMin           = 0.600;
cfg.fixMax           = 0.900;
cfg.cueDuration      = 0.200;
cfg.soaMin           = 1.200;
cfg.soaMax           = 1.600;
cfg.displayDuration  = 0.200;
cfg.responseLimit    = 1.500;

cfg.sessions         = 2;
cfg.blocksPerSession = 10;
cfg.trialsPerBlock   = 90;

cfg.Lstar            = 65;
cfg.Cstar            = 35;
cfg.baseHueDeg       = [30 120 210 300];
cfg.lowDeltaE        = 15;
cfg.highDeltaE       = 60;


%% EEG Trigger Codes (BioSemi, 8-bit: 1-255)
% Triggers mark specific events in the EEG recording.
% Each event is assigned a numeric code to identify its type and condition.
%
% 1. CUE ONSET (1-3)
%    Sent when the central arrow appears.
%       1 = Left arrow
%       2 = Right arrow
%       3 = Neutral (double-headed arrow)
%
% 2. SEARCH DISPLAY ONSET (32-157)
%    Sent when the six search items appear.
%    The code encodes three experimental variables:
%       S = Salience level
%           0: Absent (no color distractor)
%           1: Low salience
%           2: High salience
%
%       T = Target position (1-6)
%           1: 12 o'clock     4: 6 o'clock
%           2:  2 o'clock     5: 8 o'clock
%           3:  4 o'clock     6: 10 o'clock
%
%       D = Distractor position (0-6)
%           0: Absent (no distractor)
%           1-6: Same position numbering as the target
%
%    Display trigger formula:
%       Code = 32 + 42*S + 7*(T-1) + D
%
%    Example:
%       Low salience (S=1), Target at 2 o'clock (T=2),
%       Distractor at 8 o'clock (D=5)
%
%       Code = 32 + 42*1 + 7*(2-1) + 5 = 86
%
%    Cue validity is not encoded separately.
%    It can be determined from the cue direction and target position.
%
% 3. RESPONSE (240-242)
%    Sent when the participant responds or the response window expires.
%       240 = F key (backslash direction)
%       241 = J key (slash direction)
%       242 = Timeout (no valid response within 1500 ms)
%
%    Response accuracy is calculated and saved separately in the CSV.
%
% 4. BLOCK EVENTS (248-249)
%    Used to identify block boundaries in the EEG recording.
%       248 = Block start
%       249 = Block end
%
% NOTE:
%    All trigger codes fit within the BioSemi 8-bit range (1-255).
%    Session and block numbers are stored in the CSV, not encoded
%    in the trigger values.


rng('shuffle');
seedInfo = rng;
sequence = struct([]);
for session = 1:cfg.sessions
    sessionSequence = buildSequence(cfg);
    sequence = [sequence sessionSequence]; %#ok<AGROW>
end
validateSequence(sequence, cfg);

outDir = fullfile(pwd, 'data');
if ~exist(outDir, 'dir'), mkdir(outDir); end
stamp = datestr(now, 'yyyymmdd_HHMMSS');
prefix = fullfile(outDir, sprintf('TPM_%s_%s', participantID, stamp));
save([prefix '_design.mat'], 'sequence', 'cfg', 'seedInfo', 'participantID');

fid = fopen([prefix '_trials.csv'], 'w');
assert(fid ~= -1, 'Could not open the CSV file for writing.');
headers = {'participant','session','block','trial','globalTrial', ...
    'cue','validity','salience','targetPos','distractorPos', ...
    'targetHemifield','distractorHemifield','lineDirection','correctKey', ...
    'baseHue','distractorHue','actualDeltaE','cueTrigger','displayTrigger', ...
    'responseTrigger','responseKey','correct','RT','timeout', ...
    'fixDurationPlanned','SOAPlanned','fixOnset','cueOnset', ...
    'cueOffset','displayOnset','displayOffset','responseTime', ...
    'cueMissed','displayMissed','offsetMissed','triggerCueTime', ...
    'triggerDisplayTime','triggerResponseTime'};
fprintf(fid, '%s\n', strjoin(headers, ','));
fclose(fid);  % commit the header before starting the task
fid = -1;

win = [];
sp = [];
queueStarted = false;
try
    PsychDefaultSetup(1);
    Screen('Preference', 'SkipSyncTests', 0);       % DEBUG ONLY
    Screen('Preference', 'VisualDebugLevel', 0);    % DEBUG ONLY
    Screen('Preference', 'TextRenderer', 1);
    KbName('UnifyKeyNames');
    keyF = KbName('f'); keyJ = KbName('j');
    keyEsc = KbName('ESCAPE'); keySpace = KbName('space');
    keys = zeros(1, 256);
    keys([keyF keyJ keyEsc]) = 1;

    [win, winRect] = PsychImaging('OpenWindow', cfg.screenNumber, cfg.bg);
    ifi = Screen('GetFlipInterval', win);
    [cx, cy] = RectCenter(winRect);
    [widthMM, ~] = Screen('DisplaySize', cfg.screenNumber);
    if isfinite(cfg.screenWidthMM) && cfg.screenWidthMM > 0
        widthMM = cfg.screenWidthMM;
    end
    if widthMM <= 0 || ~isfinite(widthMM)
        error('Display width (mm) unavailable: set cfg.screenWidthMM manually.');
    end
    pxPerDegree = (2 * cfg.viewDistanceMM * tand(0.5)) * (RectWidth(winRect) / widthMM);
    if pxPerDegree <= 0, error('Failed to calculate visual-angle scale.'); end
    fprintf('Screen %d: %d x %d px, %.2f Hz; width %.1f mm, %.2f px/deg\n', ...
        cfg.screenNumber, RectWidth(winRect), RectHeight(winRect), 1/ifi, widthMM, pxPerDegree);
    fprintf('NOTE: Verify reported physical display width before EEG recording.\n');

    posXY = positionCoordinates(cx, cy, cfg.radiusDeg * pxPerDegree);
    shapePx = cfg.shapeDiameterDeg * pxPerDegree;
    ringPx = cfg.ringDiameterDeg * pxPerDegree;
    linePx = cfg.lineLengthDeg * pxPerDegree;
    Screen('TextFont', win, 'Arial');
    Priority(MaxPriority(win));
    HideCursor;
    ListenChar(-1);

    if cfg.useTriggers
        sp = openBioSemiTrigger(cfg.portName);
    end
    KbQueueCreate([], keys);
    KbQueueStart();
    queueStarted = true;

    instructionText = [ ...
        'VISUAL SEARCH TASK\n\n' ...
        'Six shapes will briefly appear on the screen.\n' ...
        'Your task is to find the DIAMOND among the circles.\n\n' ...
        'Look at the line inside the DIAMOND.\n' ...
        'If the line is \, press F.\n' ...
        'If the line is /, press J.\n\n' ...
        'An arrow will appear before the shapes.\n' ...
        'It may indicate which side the diamond will appear on.\n' ...
        'Sometimes the arrow will point in both directions.\n\n' ...
        'Ignore the colors of the shapes.\n' ...
        'Keep your eyes on the central dot.\n' ...
        'Respond as quickly and accurately as possible.\n\n' ...
        'Press SPACE to continue.'];

    drawMessage(win, cfg, instructionText);
    Screen('Flip', win);
    waitForSpace(keySpace, keyEsc);

    globalTrial = 0;

    for globalBlock = 1:(cfg.sessions * cfg.blocksPerSession)

        sessionNumber = ceil(globalBlock / cfg.blocksPerSession);
        block = mod(globalBlock - 1, cfg.blocksPerSession) + 1;

        drawMessage(win, cfg, 'Press SPACE to begin.');
        Screen('Flip', win);
        waitForSpace(keySpace, keyEsc);
        sendBioSemiTrigger(sp, 248);

        for trial = 1:cfg.trialsPerBlock
            globalTrial = globalTrial + 1;
            tr = sequence(globalTrial);
            tr.block = block;
            tr.trial = trial;
            tr.globalTrial = globalTrial;
            tr.fixDur = cfg.fixMin + (cfg.fixMax-cfg.fixMin)*rand;
            tr.soa = cfg.soaMin + (cfg.soaMax-cfg.soaMin)*rand;
            tr.responseKey = 'NONE';
            tr.responseTrigger = 242;
            tr.correct = 0;
            tr.rt = NaN;
            tr.timeout = 1;
            tr.responseTime = NaN;
            tr.trigResponseTime = NaN;

            % Fresh queue: prevent the prior trial's keyboard activity from carrying over.
            KbQueueFlush();

            % Fixation + persistent placeholder rings
            drawCommon(win, cfg, posXY, ringPx, cx, cy);
            [tr.fixOnset, ~, ~, ~, ~] = Screen('Flip', win);

            % Cue at fixation onset + random fixation duration.
            drawCommon(win, cfg, posXY, ringPx, cx, cy);
            drawCue(win, cfg, cx, cy, tr.cue);
            [tr.cueOnset, ~, ~, tr.cueMissed] = Screen('Flip', win, tr.fixOnset + tr.fixDur - 0.5*ifi);
            tr.trigCueTime = sendBioSemiTrigger(sp, tr.cueTrigger);

            % Cue OFF after 200 ms; placeholder rings and fixation remain.
            drawCommon(win, cfg, posXY, ringPx, cx, cy);
            [tr.cueOffset, ~, ~, ~] = Screen('Flip', win, tr.cueOnset + cfg.cueDuration - 0.5*ifi);

            % Assemble the search display before the scheduled onset.
            drawSearch(win, cfg, posXY, ringPx, shapePx, linePx, cx, cy, tr);
            KbQueueFlush();  % do not accept cue-interval responses
            [tr.displayOnset, ~, ~, tr.displayMissed] = Screen('Flip', win, tr.cueOnset + tr.soa - 0.5*ifi);
            tr.trigDisplayTime = sendBioSemiTrigger(sp, tr.displayTrigger);

            % Ensure that display stays visible for 200 ms, regardless of response.
            % Read response queue while the display is on, and continue until
            % the display has offset and a response exists OR timeout occurs.
            displayOff = false;
            responded = false;
            tr.displayOffset = NaN;
            tr.offsetMissed = NaN;
            while true
                [pressed, firstPress] = KbQueueCheck();
                if pressed
                    if firstPress(keyEsc) > 0
                        error('USER_ABORT');
                    end
                    if ~responded
                        candidates = [firstPress(keyF) firstPress(keyJ)];
                        candidates(candidates == 0) = Inf;
                        [pressedAt, choice] = min(candidates);
                        if isfinite(pressedAt) && pressedAt >= tr.displayOnset && ...
                                pressedAt <= tr.displayOnset + cfg.responseLimit
                            responded = true;
                            tr.responseTime = pressedAt;
                            tr.rt = pressedAt - tr.displayOnset;
                            tr.timeout = 0;
                            if choice == 1
                                tr.responseKey = 'F';
                                tr.responseTrigger = 240;
                                tr.correct = strcmp(tr.lineDirection, 'BACKSLASH');
                            else
                                tr.responseKey = 'J';
                                tr.responseTrigger = 241;
                                tr.correct = strcmp(tr.lineDirection, 'SLASH');
                            end
                            tr.trigResponseTime = sendBioSemiTrigger(sp, tr.responseTrigger);
                        end
                    end
                end

                if ~displayOff && GetSecs >= tr.displayOnset + cfg.displayDuration - ifi
                    drawCommon(win, cfg, posXY, ringPx, cx, cy);
                    [tr.displayOffset, ~, ~, tr.offsetMissed] = Screen('Flip', win, ...
                        tr.displayOnset + cfg.displayDuration - 0.5*ifi);
                    displayOff = true;
                end
                if displayOff && (responded || GetSecs >= tr.displayOnset + cfg.responseLimit)
                    break;
                end
                WaitSecs('YieldSecs', 0.001);
            end
            if ~responded
                tr.trigResponseTime = sendBioSemiTrigger(sp, 242);
            end

            fid = fopen([prefix '_trials.csv'], 'a');
            assert(fid ~= -1, 'Failed to open CSV for append.');
            fprintf(fid, '%s\n', encodeCSV(tr, participantID, sessionNumber));
            fclose(fid);  % commit each finished trial (survives an abort)
            fid = -1;
            fprintf('S%d B%02d T%02d | %s | %s | T%d D%d | %s | %s | RT %.3f\n', ...
                sessionNumber, block, trial, tr.cue, tr.salienceName, ...
                tr.targetPos, tr.distractorPos, tr.lineDirection, tr.responseKey, tr.rt);
        end
        sendBioSemiTrigger(sp, 249);
        if globalBlock < cfg.sessions * cfg.blocksPerSession

            if block == cfg.blocksPerSession

                % Longer break between sessions
                drawMessage(win, cfg, ...
                    ['You may take a longer break now.\n\n' ...
                    'Press SPACE when you are ready to continue.']);

            else

                % Regular break between blocks
                drawMessage(win, cfg, ...
                    ['Take a short break.\n\n' ...
                    'Press SPACE when you are ready to continue.']);

            end

            Screen('Flip', win);
            waitForSpace(keySpace, keyEsc);

        end
    end

    drawMessage(win, cfg, 'Experiment complete.\n\nAll 1800 trials finished.\n\nPress SPACE to finish.');
    Screen('Flip', win);
    waitForSpace(keySpace, keyEsc);
    fprintf('Completed. CSV saved to: %s_trials.csv\n', prefix);
catch ME
    if strcmp(ME.message, 'USER_ABORT')
        fprintf('Experiment aborted. Completed trials remain saved in CSV.\n');
    else
        fprintf(2, 'Experiment error: %s\n', ME.message);
        cleanup(win, sp, fid, queueStarted);
        rethrow(ME);
    end
end
cleanup(win, sp, fid, queueStarted);
end

%% Trial design
function sequence = buildSequence(cfg)
sequence = struct([]);
for b = 1:cfg.blocksPerSession
    blockTrials = struct([]);
    % 45 valid, 15 invalid, 30 neutral trials per block. (total 90 trials)
    for cueType = 1:3  % 1=valid, 2=invalid, 3=neutral
        for sal = 0:2  % 0=absent, 1=low, 2=high
            if cueType == 1, n = 15; elseif cueType == 2, n = 5; else, n = 10; end
            for k = 1:n
                isValid = (cueType == 1);
                isNeutral = (cueType == 3);
                if isNeutral
                    targetMidline = (k <= 5);
                    if targetMidline, tp = samplePosition([1 4]);
                    else, tp = samplePosition([2 3 5 6]); end
                    cp = 0; % neutral
                else
                    cp = samplePosition([1 2]); % 1=left, 2=right
                    if isValid, targetSide = cp;
                    else, targetSide = 3 - cp; end
                    tp = samplePosition(sidePositions(targetSide));
                end
                if sal == 0
                    dp = 0;
                elseif isNeutral
                    if ismember(tp, [1 4]), dp = samplePosition([2 3 5 6]);
                    else, dp = samplePosition([1 4]); end
                elseif isValid
                    % For each salience, 3 same-side, 6 opposite, 6 midline.
                    if k <= 3
                        available = setdiff(sidePositions(cp), tp);
                    elseif k <= 9
                        available = sidePositions(3-cp);
                    else
                        available = [1 4];
                    end
                    dp = samplePosition(available);
                else
                    dp = samplePosition(setdiff(1:6, tp));
                end
                if cp == 1, cueName = 'LEFT';
                elseif cp == 2, cueName = 'RIGHT';
                else, cueName = 'NEUTRAL'; end
                if isNeutral, validityName = 'NEUTRAL';
                elseif isValid, validityName = 'VALID';
                else, validityName = 'INVALID'; end
                if sal == 0, salName = 'ABSENT';
                elseif sal == 1, salName = 'LOW';
                else, salName = 'HIGH'; end
                baseHue = cfg.baseHueDeg(randi(numel(cfg.baseHueDeg)));
                if sal == 0
                    singletonHue = NaN; actualDeltaE = 0;
                else
                    if sal == 1, deltaE = cfg.lowDeltaE;
                    else, deltaE = cfg.highDeltaE; end
                    hueShift = 2*asind(deltaE/(2*cfg.Cstar));
                    singletonHue = mod(baseHue + (2*randi(2)-3)*hueShift, 360);
                    actualDeltaE = 2*cfg.Cstar*sind(hueShift/2);
                end
                rgbBase = labHueToRGB(cfg.Lstar, cfg.Cstar, baseHue);
                if sal == 0, rgbSingleton = rgbBase;
                else, rgbSingleton = labHueToRGB(cfg.Lstar, cfg.Cstar, singletonHue); end
                if rand < 0.5, direction = 'BACKSLASH'; key = 'F';
                else, direction = 'SLASH'; key = 'J'; end
                % Assign line orientations independently to all six positions.
                % The diamond target retains the direction that determines the correct key.
                lineDirections = cell(1, 6);
                for p = 1:6
                    if p == tp
                        lineDirections{p} = direction;
                    elseif rand < 0.5
                        lineDirections{p} = 'BACKSLASH';
                    else
                        lineDirections{p} = 'SLASH';
                    end
                end
                cueCode = cp; if cp == 0, cueCode = 3; end
                displayCode = 32 + 42*sal + 7*(tp-1) + dp;
                tr = struct('cue',cueName,'validity',validityName, ...
                    'cueTrigger',cueCode,'displayTrigger',displayCode, ...
                    'salience',sal,'salienceName',salName,'targetPos',tp, ...
                    'distractorPos',dp,'targetHemifield',hemifield(tp), ...
                    'distractorHemifield',hemifield(dp), ...
                    'lineDirection',direction,'lineDirections',{lineDirections},'correctKey',key, ...
                    'baseHue',baseHue,'distractorHue',singletonHue, ...
                    'actualDeltaE',actualDeltaE, ...
                    'baseRGB',rgbBase,'distractorRGB',rgbSingleton);
                if isempty(blockTrials), blockTrials = tr;
                else, blockTrials(end+1) = tr; end %#ok<AGROW>
            end
        end
    end
    blockTrials = blockTrials(randperm(numel(blockTrials)));
    if isempty(sequence), sequence = blockTrials;
    else, sequence = [sequence blockTrials]; end %#ok<AGROW>
end
end

function validateSequence(sequence, cfg)

assert(numel(sequence) == ...
    cfg.sessions * cfg.blocksPerSession * cfg.trialsPerBlock);

for b = 1:(cfg.sessions * cfg.blocksPerSession)
    ts = sequence((b-1)*cfg.trialsPerBlock+1:b*cfg.trialsPerBlock);
    for s = 0:2
        assert(sum([ts.salience] == s) == 30);
        for c = {'VALID','INVALID','NEUTRAL'}
            cue = c{1};
            if strcmp(cue,'VALID'), count=15;
            elseif strcmp(cue,'INVALID'), count=5;
            else, count=10; end
            assert(sum(strcmp({ts.validity},cue) & [ts.salience] == s) == count);
        end
        if s>0
            valid = ts(strcmp({ts.validity},'VALID') & [ts.salience] == s);
            same = 0; opposite = 0; midline = 0;
            for j = 1:numel(valid)
                dh = valid(j).distractorHemifield;
                if dh==0, midline=midline+1;
                elseif dh==valid(j).targetHemifield, same=same+1;
                else, opposite=opposite+1; end
            end
            assert(same==3 && opposite==6 && midline==6);
        end
    end
    for j=1:numel(ts)
        assert(ts(j).targetPos~=ts(j).distractorPos);
        assert(ts(j).cueTrigger>=1 && ts(j).cueTrigger<=3);
        assert(ts(j).displayTrigger>=32 && ts(j).displayTrigger<=255);
    end
end
end

%% Drawing
function xy = positionCoordinates(cx,cy,r)
% 12, 2, 4, 6, 8, 10 o'clock. Screen Y increases downwards.
angles = [-90 -30 30 90 150 210];
xy = [cx + r*cosd(angles); cy + r*sind(angles)];
end
function drawCommon(win,cfg,xy,ringPx,cx,cy)
Screen('FillRect',win,cfg.bg);
for i=1:6
    rect = CenterRectOnPointd([0 0 ringPx ringPx], xy(1,i), xy(2,i));
    Screen('FrameOval', win, cfg.ringColor, rect, cfg.ringWidthPx);
end
Screen('DrawDots',win,[cx;cy],cfg.fixDiameterPx,cfg.fixColor,[],2);
end

function drawCue(win, cfg, cx, cy, cue)

arrowLength = 70;
shaftHalf   = 5;
headLength  = 18;
headHalf    = 17;

L = arrowLength / 2;
H = headLength;
S = shaftHalf;
A = headHalf;

if strcmp(cue, 'RIGHT')
    vertices = [
        -L,   -S;
        L-H, -S;
        L-H, -A;
        L,    0;
        L-H,  A;
        L-H,  S;
        -L,    S
        ];
elseif strcmp(cue, 'LEFT')
    vertices = [
        L,    -S;
        -L+H,  -S;
        -L+H,  -A;
        -L,     0;
        -L+H,   A;
        -L+H,   S;
        L,     S
        ];
else  % NEUTRAL
    vertices = [
        -L,     0;
        -L+H,  -A;
        -L+H,  -S;
        L-H,  -S;
        L-H,  -A;
        L,     0;
        L-H,   A;
        L-H,   S;
        -L+H,   S;
        -L+H,   A
        ];
end

% Translate to screen center
vertices(:,1) = vertices(:,1) + cx;
vertices(:,2) = vertices(:,2) + cy;

Screen('FillPoly', win, cfg.fixColor, vertices, 0);
end

function drawSearch(win,cfg,xy,ringPx,shapePx,linePx,cx,cy,tr)
drawCommon(win,cfg,xy,ringPx,cx,cy);
for i = 1:6
    x=xy(1,i); y=xy(2,i);
    col=tr.baseRGB;
    if i==tr.distractorPos, col=tr.distractorRGB; end
    r=shapePx/2;
    if i==tr.targetPos
        Screen('FillPoly',win,col,[x y-r; x+r y; x y+r; x-r y],1);
    else
        Screen('FillOval',win,col,[x-r y-r x+r y+r]);
    end
    half=linePx/(2*sqrt(2));
    if strcmp(tr.lineDirections{i},'BACKSLASH')
        Screen('DrawLine',win,cfg.lineColor,x-half,y-half,x+half,y+half,cfg.lineWidthPx);
    else
        Screen('DrawLine',win,cfg.lineColor,x-half,y+half,x+half,y-half,cfg.lineWidthPx);
    end
end
end
function drawMessage(win,cfg,str)
Screen('FillRect',win,cfg.bg);
Screen('TextFont',win,'Arial');
Screen('TextSize',win,cfg.instructionPx);
DrawFormattedText(win,str,'center','center',[255 255 255],60,[],[],1.4);
end

%% BioSemi and keys
function sp = openBioSemiTrigger(portName)
ports = serialportlist('available');
if ~any(strcmp(ports,portName))
    error('BioSemi port %s not found. Available: %s',portName,strjoin(cellstr(ports),', '));
end
sp = serialport(portName,115200,'DataBits',8,'StopBits',1);
fprintf('BioSemi trigger connected: %s\n',portName);
end
function t = sendBioSemiTrigger(sp, code)
    t = NaN;
    if isempty(sp), return; end
    assert(code >= 1 && code <= 255 && code == fix(code));
    t = GetSecs;
    write(sp, uint8(code), 'uint8');
end
function waitForSpace(spaceKey,escKey)
KbReleaseWait;
while true
    [down,~,keyCode]=KbCheck;
    if down
        if keyCode(escKey), error('USER_ABORT'); end
        if keyCode(spaceKey)
            KbReleaseWait;
            return;
        end
    end
    WaitSecs('YieldSecs',0.01);
end
end
function cleanup(win,sp,fid,queueStarted)
if queueStarted
    try, KbQueueStop(); KbQueueRelease(); catch, end
end
if fid~=-1, try, fclose(fid); catch, end, end
if ~isempty(sp), try, delete(sp); catch, end, end
try, Priority(0); catch, end
try, ListenChar(0); catch, end
try, ShowCursor; catch, end
if ~isempty(win), try, Screen('CloseAll'); catch, end, end
end

%% Data and utilities
function txt = encodeCSV(t,id,session)
items = {id,session,t.block,t.trial,t.globalTrial,t.cue,t.validity, ...
    t.salienceName,t.targetPos,t.distractorPos,t.targetHemifield, ...
    t.distractorHemifield,t.lineDirection,t.correctKey,t.baseHue, ...
    t.distractorHue,t.actualDeltaE,t.cueTrigger,t.displayTrigger, ...
    t.responseTrigger,t.responseKey,t.correct,t.rt,t.timeout, ...
    t.fixDur,t.soa,t.fixOnset,t.cueOnset,t.cueOffset, ...
    t.displayOnset,t.displayOffset,t.responseTime,t.cueMissed, ...
    t.displayMissed,t.offsetMissed,t.trigCueTime,t.trigDisplayTime,t.trigResponseTime};
vals = cell(size(items));
for k=1:numel(items)
    if isnumeric(items{k}), vals{k}=sprintf('%.17g',items{k});
    else, vals{k}=char(items{k}); end
end
txt=strjoin(vals,',');
end
function p=samplePosition(candidates)
p=candidates(randi(numel(candidates)));
end
function p=sidePositions(side)
if side==1, p=[5 6];
else, p=[2 3]; end
end
function h=hemifield(position)
if position==0 || position==1 || position==4, h=0;
elseif position==2 || position==3, h=2;
else, h=1; end
end
function rgb=labHueToRGB(L,C,H)
% CIELAB (D65) -> sRGB. Clipping makes desired DeltaE inaccurate.
a=C*cosd(H); b=C*sind(H);
fy=(L+16)/116; fx=fy+a/500; fz=fy-b/200;
epsilon=216/24389; kappa=24389/27;
fx3=fx^3; fy3=fy^3; fz3=fz^3;
if fx3>epsilon, xr=fx3; else, xr=(116*fx-16)/kappa; end
if fy3>epsilon, yr=fy3; else, yr=(116*fy-16)/kappa; end
if fz3>epsilon, zr=fz3; else, zr=(116*fz-16)/kappa; end
XYZ=[xr*.95047; yr; zr*1.08883];
linear=[3.2404542 -1.5371385 -0.4985314; ...
       -0.9692660  1.8760108  0.0415560; ...
        0.0556434 -0.2040259  1.0572252]*XYZ;
if any(linear < 0 | linear > 1)
    warning('Out-of-gamut Lab color (L %.1f C %.1f H %.1f): RGB clipped.',L,C,H);
end
linear=max(0,min(1,linear));
srgb=zeros(3,1);
for n=1:3
    if linear(n)<=0.0031308, srgb(n)=12.92*linear(n);
    else, srgb(n)=1.055*linear(n)^(1/2.4)-0.055; end
end
rgb=(255*srgb)';
end