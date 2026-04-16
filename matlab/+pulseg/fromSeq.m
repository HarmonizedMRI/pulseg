function psq = fromSeq(seqarg, varargin)
% function psq = fromSeq(seqarg, varargin)
%
% Convert a Pulseq file (http://pulseq.github.io/) to a PulSeg struct.
%
% Input
%   seqarg     a Pulseq sequence object, or name of a .seq file
%
% Input options with defaults
%   verbose               true/FALSE    Print some info to the terminal
%   usesRotationEvents    TRUE/false    If false, this script tries to estimate 
%                                       in plane (2D, x-y) rotations from the gradient shapes.
%   P                     [3 3]         A global gradient projection matrix. Default: eye(3).
%                                       The 3x3 'rotation' matrix stored in the psq object is actually P*R,
%                                       where R is the rotation matrix. For example, to only play the x gradient,
%                                       set P = [1 0 0; 0 0 0; 0 0 0]
%
% Output
%   psq        PulSeq sequence struct, see github/HarmonizedMRI/pulseg/docs/spec.md

% Definitions:
% n, row        row index in .seq file
% i             segment array index, starting from 1
% j             block number within a segment, starting from 1


%% parse inputs

% defaults
arg.verbose = false;
arg.usesRotationEvents = true;
arg.P = eye(3);

% Substitute specified system values as appropriate (from MIRT toolbox)
arg = vararg_pair(arg, varargin);


%% Get seq object
if isa(seqarg, 'char')
    fprintf(sprintf('Reading %s ... ', seqarg));
    seq = mr.Sequence();
    seq.read(seqarg);
    fprintf(' done\n');
else
    if ~isa(seqarg, 'mr.Sequence')
        error('First argument is not an mr.Sequence object');
    end
    seq = seqarg;
end

nEvents = 7;   % Pulseq 1.4.0 
blockEvents = cell2mat(seq.blockEvents);
blockEvents = reshape(blockEvents, [nEvents, length(seq.blockEvents)]).'; 

% number of blocks (rows in .seq file) to step through
psq.nMax = size(blockEvents, 1);


%% Get TRID labels and corresponding row indices for all segment instances
nTRIDlabels = 0;
%fprintf('Getting TRID labels (%d
textprogressbar('fromSeq(): Reading TRID labels and counting ADC events: ');
psq.nReadouts = 0;
nMaxTRIDs = 1000; % infinite number
TRIDlist = 1:1000;
for n = 1:psq.nMax
    textprogressbar(n/psq.nMax*100);

    b = seq.getBlock(n);

    if ~isempty(b.adc)
        psq.nReadouts = psq.nReadouts + 1;
    end

    % get TRID label if present
    if isfield(b, 'label') 
        for ii = 1:length(b.label)
            if strcmp(b.label(ii).label, 'TRID')
                nTRIDlabels = nTRIDlabels + 1;
                tridLabels.val(nTRIDlabels) = b.label(ii).value;
                trids(n) = b.label(ii).value;
                tridLabels.index(nTRIDlabels) = n;
                break;
            end
        end
    end
end
textprogressbar(''); 

%% Get list of (virtual) segments.
%% These are distinct from segment 'instances'.

[uniqueTridLabels, I] = unique(tridLabels.val);
nBlocksPerTridLabel = diff([tridLabels.index psq.nMax+1]);
psq.nSegments = length(uniqueTridLabels);
for i = 1:psq.nSegments
    psq.segments(i).nBlocksInSegment = nBlocksPerTridLabel(I(i));
    psq.segments(i).TRID = tridLabels.val(I(i));
    psq.segments(i).ID = i;
    psq.segments(i).rows = tridLabels.index(I(i)) + [0:psq.segments(i).nBlocksInSegment-1];
end


%% Detect variable delay blocks
psq.nParentBlocks = 0;
maxnBlocksInSegment = 0;
for i = 1:psq.nSegments
    if psq.segments(i).nBlocksInSegment > maxnBlocksInSegment
        maxnBlocksInSegment = psq.segments(i).nBlocksInSegment;
    end
end
isVariableDelay = false(psq.nSegments, maxnBlocksInSegment);
blockDuration = -ones(psq.nSegments, maxnBlocksInSegment); % block instance durations
n = tridLabels.index(1);  % start of first segment instance

while n < psq.nMax + 1
    i = find(uniqueTridLabels == trids(n));  % segment array index

    for j = 1:psq.segments(i).nBlocksInSegment

        b = seq.getBlock(n);
        T = getblocktype(b);

        if blockDuration(i,j) == -1
            blockDuration(i,j) = b.blockDuration;  % first instance of block (i,j)
        else
            if b.blockDuration ~= blockDuration(i,j)  % duration is different from a previous instance
                if T(4)
                    isVariableDelay(i,j) = true;
                    n = n + 1;
                    continue;  % go to next j iteration
                else
                    error(sprintf('(row %d: segment %d, block %d) Non-delay blocks must have the same duration in all segment instances', n, i, j));
                end
            end
        end
        n = n + 1;
    end
end


%% Get parent blocks, by parsing first instance of each segment.
%% Also fill in the sequence of parent blocks for each segment.
%% Static pure delay blocks are assigned parent block ID = 0
%% Variable pure delay blocks are assigned parent block ID = -1

for i = 1:psq.nSegments

    for j = 1:psq.segments(i).nBlocksInSegment

        n = psq.segments(i).rows(j);

        b = seq.getBlock(n);
        T = getblocktype(b);

        % Pure delay block (constant or variable)
        if T(4) == 1
            psq.segments(i).blockIDs(j) = 0 - isVariableDelay(i,j);
            continue;
        end

        % Not a pure delay block.
        % Now check if block is similar to an existing parent block
        issame = false;
        for p = 1:psq.nParentBlocks
            np = psq.parentBlocks(p).row; 
            if compareblocks(seq, blockEvents(n,:), blockEvents(np,:), n, np)
                issame = true;
                psq.segments(i).blockIDs(j) = p;
                break;
            end
        end

        % If not similar, add as a new parent block
        if ~issame
            if arg.verbose
                fprintf('\nFound new parent block on line %d\n', n);
            end
            psq.nParentBlocks = psq.nParentBlocks + 1;
            psq.parentBlocks(psq.nParentBlocks).row = n;
            psq.parentBlocks(psq.nParentBlocks).block = b;
            psq.parentBlocks(psq.nParentBlocks).block.ID = psq.nParentBlocks;
            psq.segments(i).blockIDs(j) = psq.nParentBlocks;
        end
    end
end

for p = 1:psq.nParentBlocks
    psq.parentBlocks(p).ID = p;
end

%% Get dynamic scan information, including cardiac trigger
%% and gradient rotation.
%% NB! The last block with non-identity rotation in a segment 
%% determines the rotation for the whole segment.
psq.loop = zeros(psq.nMax, 23);
physioTrigger = false;
n = tridLabels.index(1);  % start of first segment instance
textprogressbar('fromSeq(): Getting dynamic scan information: ');
while n < psq.nMax + 1
    textprogressbar(n/psq.nMax*100);
    
    b = seq.getBlock(n);

    % skip if not the first block in segment instance
    if trids(n) == 0
        n = n + 1;
        continue;
    end

    % Loop over blocks in segment instance.
    physioTrigger = false;
    i = find(uniqueTridLabels == trids(n));  % segment array index

    R = eye(3);  % default rotation for this segment

    for j = 1:psq.segments(i).nBlocksInSegment
        b = seq.getBlock(n);

        % get cardiac trigger
        T = getblocktype(b);
        physioTrigger = T(3);
        p = psq.segments(i).blockIDs(j);  % parent block index

        if p < 1  
            % pure delay block (constant or variable)
            psq.loop(n,:) = getdynamics(b, i, p, physioTrigger, []);
            n = n + 1;
            continue;
        else
            psq.loop(n,:) = getdynamics(b, i, p, physioTrigger, psq.parentBlocks(p).block);
        end

        % Get rotation
        if arg.usesRotationEvents
            if isfield(b, 'rotation')
                if strcmp(b.rotation.type, 'rot3D')
                    R = mr.aux.quat.toRotMat(b.rotation.rotQuaternion);
                end
            end
        else
            % try to detect 2D rotations by analyzing the gradient shapes
            [Rtmp, scale] = getrotation(b, psq.parentBlocks(p).block);
            
            if ~isempty(Rtmp)
                if norm(Rtmp - eye(3), "fro") > 1e-6
                    % Found a non-identiy rotation, so use it
                    % (unless overwritten by a later block in this segment)
                    R = Rtmp;

                    % set gradient amplitudes equal to those in the parent block (possibly scaled)
                    psq.loop(n, [6 8 10]) = scale * psq.loop(psq.parentBlocks(p).row, [6 8 10]);
                end
            end
        end

        n = n + 1;
    end

    % Apply projection matrix
    R = arg.P*R;

    % Set rotation for last block in segment instance; 
    % the interpreter uses this to set the rotation for the whole segment
    R = R';
    psq.loop(n-1, 15:23) = R(:)';   % write R in row-major order

end
textprogressbar(100);
textprogressbar(''); 


%% Set sequence duration
% This is a bit inaccurate for now -- doesn't account for ssi time  TODO
psq.duration = seq.duration;


%% Remove zero-duration (label-only) blocks from psq.loop
%psq.loop(psq.loop(:,1) == 0, :) = [];
%psq.nMax = size(psq.loop,1);


%% Check that the execution of blocks throughout the sequence
%% is consistent with the segment definitions
n = 1;
while n < psq.nMax
    i = psq.loop(n, 1);  % segment index

    if (n + psq.segments(i).nBlocksInSegment) > psq.nMax
        break;
    end

    % loop through blocks in segment
    for j = 1:psq.segments(i).nBlocksInSegment

        % compare parent block id in psq.loop against block id in psq.segments(i)
        p = psq.loop(n, 2);  % parent block id
        p_ij = psq.segments(i).blockIDs(j);
        msg = ['Sequence contains inconsistent segment definitions. ' ...
               'This may occur due to programming error (possibly fatal), ' ...
               'or if an arbitrary gradient resembles that from another block ' ...
               'except with opposite sign or scaled by zero (which is probably ok). ' ...
               'Often, a solution to this is to scale gradients to "eps" instead of ' ...
               'identically zero, when calling mr.scaleGrad().'];
        if p ~= p_ij
            warning(sprintf('%s\nExpected parent block ID %d, found %d (block %d)', msg, p_ij, p, n));
        end

        n = n + 1;
    end
end

%% Gradient heating related calculations

% Get block/row index corresponding to the beginning of the segment instance
% instance with the largest combined (all axes) gradient energy.

% initialize max energy field
for i = 1:psq.nSegments
    psq.segments(i).Emax.val = 0;
    psq.segments(i).Emax.n = 1;
end
   
% find segment instance with max energy
n = 1;
while n < psq.nMax
    % Calculate total energy in segment instance
    i = psq.loop(n, 1);  % segment index
    Etmp.gx = 0; Etmp.gy = 0; Etmp.gz = 0;
    nFirst = n;
    for j = 1:psq.segments(i).nBlocksInSegment  
        Etmp.gx = Etmp.gx + psq.loop(n, 11);
        Etmp.gy = Etmp.gy + psq.loop(n, 12);
        Etmp.gz = Etmp.gz + psq.loop(n, 13);
        n = n + 1;
    end
    Etmp.all = Etmp.gx + Etmp.gy + Etmp.gz;

    % update Emax field
    if Etmp.all > psq.segments(i).Emax.val
        psq.segments(i).Emax.n = nFirst;
        psq.segments(i).Emax.val = Etmp.all;
    end
end

