function pulseg_ir = import(seqarg, varargin)
% IMPORT Convert a Pulseq (.seq) file or sequence object to a PulSeg IR struct.
%
% Syntax:
%   pulseg_ir = pulseg.import(seq)
%
% Input
%   seq      A Pulseq sequence object, or name of a .seq file
%
% Input options with defaults
%   verbose               true/FALSE    Print some info to the terminal
%   usesRotationEvents    TRUE/false    If false, this script tries to estimate 
%                                       in plane (2D, x-y) rotations from the gradient shapes.
% Output
%   pulseg_ir        PulSeq sequence struct, see github/HarmonizedMRI/pulseg/docs/spec.md

% Definitions:
% n, row        row index in .seq file
% i             segment array index, starting from 1
% j             block number within a segment, starting from 1


%% parse inputs

% defaults
arg.verbose = false;
arg.usesRotationEvents = true;

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
pulseg_ir.nMax = size(blockEvents, 1);


%% Get TRID labels and corresponding row indices for all segment instances
nTRIDlabels = 0;
%fprintf('Getting TRID labels (%d
textprogressbar('import(): Reading TRID labels and counting ADC events: ');
pulseg_ir.nReadouts = 0;
nMaxTRIDs = 1000; % infinite number
TRIDlist = 1:1000;
for n = 1:pulseg_ir.nMax
    textprogressbar(n/pulseg_ir.nMax*100);

    b = seq.getBlock(n);

    if ~isempty(b.adc)
        pulseg_ir.nReadouts = pulseg_ir.nReadouts + 1;
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
nBlocksPerTridLabel = diff([tridLabels.index pulseg_ir.nMax+1]);
pulseg_ir.nSegments = length(uniqueTridLabels);
for i = 1:pulseg_ir.nSegments
    pulseg_ir.virtual_segments(i).n_blocks_in_segment = nBlocksPerTridLabel(I(i));
    pulseg_ir.virtual_segments(i).TRID = tridLabels.val(I(i));
    pulseg_ir.virtual_segments(i).ID = i;
    pulseg_ir.virtual_segments(i).rows = tridLabels.index(I(i)) + [0:pulseg_ir.virtual_segments(i).n_blocks_in_segment-1];
end


%% Detect variable delay blocks
pulseg_ir.n_base_blocks = 0;
max_n_blocks_in_segment = 0;
for i = 1:pulseg_ir.nSegments
    if pulseg_ir.virtual_segments(i).n_blocks_in_segment > max_n_blocks_in_segment
        max_n_blocks_in_segment = pulseg_ir.virtual_segments(i).n_blocks_in_segment;
    end
end
isVariableDelay = false(pulseg_ir.nSegments, max_n_blocks_in_segment);
blockDuration = -ones(pulseg_ir.nSegments, max_n_blocks_in_segment); % block instance durations
n = tridLabels.index(1);  % start of first segment instance

while n < pulseg_ir.nMax + 1
    i = find(uniqueTridLabels == trids(n));  % segment array index

    for j = 1:pulseg_ir.virtual_segments(i).n_blocks_in_segment

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


%% Get base blocks, by parsing first instance of each segment.
%% Also fill in the sequence of base blocks for each segment.
%% Static pure delay blocks are assigned base block ID = 0
%% Variable pure delay blocks are assigned base block ID = -1

for i = 1:pulseg_ir.nSegments

    for j = 1:pulseg_ir.virtual_segments(i).n_blocks_in_segment

        n = pulseg_ir.virtual_segments(i).rows(j);

        b = seq.getBlock(n);
        T = getblocktype(b);

        % Pure delay block identification
        if T(4) == 1
            if isVariableDelay(i,j)
                pulseg_ir.virtual_segments(i).blockIDs(j) = -1; % Implicit Variable Delay
            else
                pulseg_ir.virtual_segments(i).blockIDs(j) = 0; % Implicit Constant Delay
            end
            continue;
        end

        % Not a pure delay block.
        % Now check if block is similar to an existing base block
        issame = false;
        for p = 1:pulseg_ir.n_base_blocks
            np = pulseg_ir.base_blocks(p).row; 
            if compareblocks(seq, blockEvents(n,:), blockEvents(np,:), n, np)
                issame = true;
                pulseg_ir.virtual_segments(i).blockIDs(j) = p;
                break;
            end
        end

        % If not similar, add as a new base block
        if ~issame
            if arg.verbose
                fprintf('\nFound new base block on line %d\n', n);
            end
            pulseg_ir.n_base_blocks = pulseg_ir.n_base_blocks + 1;
            assigned_id = pulseg_ir.n_base_blocks + 1;
            pulseg_ir.base_blocks(pulseg_ir.n_base_blocks).row = n;
            pulseg_ir.base_blocks(pulseg_ir.n_base_blocks).block = b;
            pulseg_ir.base_blocks(pulseg_ir.n_base_blocks).block.ID = pulseg_ir.n_base_blocks;
            pulseg_ir.virtual_segments(i).blockIDs(j) = pulseg_ir.n_base_blocks;
        end
    end
end

for p = 1:pulseg_ir.n_base_blocks
    pulseg_ir.base_blocks(p).ID = p;
end

%% Get dynamic scan information, including cardiac trigger
%% and gradient rotation.
%% NB! The last block with non-identity rotation in a segment 
%% determines the rotation for the whole segment.
pulseg_ir.loop = zeros(pulseg_ir.nMax, 23);
physioTrigger = false;
n = tridLabels.index(1);  % start of first segment instance
textprogressbar('import(): Getting dynamic scan information: ');
while n < pulseg_ir.nMax + 1
    textprogressbar(n/pulseg_ir.nMax*100);
    
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

    for j = 1:pulseg_ir.virtual_segments(i).n_blocks_in_segment
        b = seq.getBlock(n);

        % get cardiac trigger
        T = getblocktype(b);
        physioTrigger = T(3);

        % base block index
        p = pulseg_ir.virtual_segments(i).blockIDs(j);  

        if p < 1  
            % pure delay block (constant or variable)
            pulseg_ir.loop(n,:) = getdynamics(b, i, p, physioTrigger, []);
            n = n + 1;
            continue;
        else
            pulseg_ir.loop(n,:) = getdynamics(b, i, p, physioTrigger, pulseg_ir.base_blocks(p).block);
        end

        % Get rotation
        if isfield(b, 'rotation')
            if strcmp(b.rotation.type, 'rot3D')
                R = mr.aux.quat.toRotMat(b.rotation.rotQuaternion);
            end
        end

        n = n + 1;
    end

    % Set rotation for last block in segment instance; 
    % the interpreter uses this to set the rotation for the whole segment
    R = R';
    pulseg_ir.loop(n-1, 15:23) = R(:)';   % write R in row-major order

end
textprogressbar(100);
textprogressbar(''); 


%% Set sequence duration
% This is a bit inaccurate for now -- doesn't account for ssi time  TODO
pulseg_ir.duration = seq.duration;


%% Remove zero-duration (label-only) blocks from pulseg_ir.loop
%pulseg_ir.loop(pulseg_ir.loop(:,1) == 0, :) = [];
%pulseg_ir.nMax = size(pulseg_ir.loop,1);


%% Check that the execution of blocks throughout the sequence
%% is consistent with the segment definitions
n = 1;
while n < pulseg_ir.nMax
    i = pulseg_ir.loop(n, 1);  % segment index

    if (n + pulseg_ir.virtual_segments(i).n_blocks_in_segment) > pulseg_ir.nMax
        break;
    end

    % loop through blocks in segment
    for j = 1:pulseg_ir.virtual_segments(i).n_blocks_in_segment

        % compare base block id in pulseg_ir.loop against block id in pulseg_ir.virtual_segments(i)
        p = pulseg_ir.loop(n, 2);  % base block id
        p_ij = pulseg_ir.virtual_segments(i).blockIDs(j);
        msg = ['Sequence contains inconsistent segment definitions. ' ...
               'This may occur due to programming error (possibly fatal), ' ...
               'or if an arbitrary gradient resembles that from another block ' ...
               'except with opposite sign or scaled by zero (which is probably ok). ' ...
               'Often, a solution to this is to scale gradients to "eps" instead of ' ...
               'identically zero, when calling mr.scaleGrad().'];
        if p ~= p_ij
            warning(sprintf('%s\nExpected base block ID %d, found %d (block %d)', msg, p_ij, p, n));
        end

        n = n + 1;
    end
end

%% Gradient heating related calculations

% Get block/row index corresponding to the beginning of the segment instance
% instance with the largest combined (all axes) gradient energy.

% initialize max energy field
for i = 1:pulseg_ir.nSegments
    pulseg_ir.virtual_segments(i).Emax.val = 0;
    pulseg_ir.virtual_segments(i).Emax.n = 1;
end
   
% find segment instance with max energy
n = 1;
while n < pulseg_ir.nMax
    % Calculate total energy in segment instance
    i = pulseg_ir.loop(n, 1);  % segment index
    Etmp.gx = 0; Etmp.gy = 0; Etmp.gz = 0;
    nFirst = n;
    for j = 1:pulseg_ir.virtual_segments(i).n_blocks_in_segment  
        Etmp.gx = Etmp.gx + pulseg_ir.loop(n, 11);
        Etmp.gy = Etmp.gy + pulseg_ir.loop(n, 12);
        Etmp.gz = Etmp.gz + pulseg_ir.loop(n, 13);
        n = n + 1;
    end
    Etmp.all = Etmp.gx + Etmp.gy + Etmp.gz;

    % update Emax field
    if Etmp.all > pulseg_ir.virtual_segments(i).Emax.val
        pulseg_ir.virtual_segments(i).Emax.n = nFirst;
        pulseg_ir.virtual_segments(i).Emax.val = Etmp.all;
    end
end

