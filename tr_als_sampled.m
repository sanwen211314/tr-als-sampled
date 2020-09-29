function cores = tr_als_sampled(X, ranks, embedding_dims, varargin)
%tr_als_sampled Compute tensor ring decomposition via sampled ALS
%
%For loading from file: It is assumed that the tensor is stored in a
%variable Y in the mat file.
%
%cores = tr_als(X, ranks, embedding_dims) computes a tensor ring (TR) 
%decomposition of the input N-dimensional array X by sampling the LS
%problems using sketch sizes for each dimension given in embedding_dims.
%Ranks is a length-N vector containing the target ranks. The output cores
%is a cell containing the N cores tensors, each represented as a 3-way
%array.
%
%cores = tr_als(___, 'tol', tol) is an optional argument that controls the
%termination tolerance. If the change in the relative error is less than
%tol at the conclusion of a main loop iteration, the algorithm terminates.
%Default is 1e-3.
%
%cores = tr_als(___, 'maxiters', maxiters) is an optional argument that
%controls the maximum number of main loop iterations. The default is 50.
%
%cores = tr_als(___, 'verbose', verbose) is an optional argument that
%controls the amount of information printed to the terminal during
%execution. Setting verbose to true will result in more print out. Default
%is false.

%% Add relevant paths

addpath('help_functions\mtimesx\mtimesx_20110223')
mtimesx('SPEED');

%% Handle inputs 

% Optional inputs
params = inputParser;
addParameter(params, 'tol', 1e-3, @isscalar);
addParameter(params, 'maxiters', 50, @(x) isscalar(x) & x > 0);
addParameter(params, 'resample', true, @isscalar);
addParameter(params, 'verbose', false, @isscalar);
addParameter(params, 'no_mat_inc', false);
parse(params, varargin{:});

tol = params.Results.tol;
maxiters = params.Results.maxiters;
resample = params.Results.resample;
verbose = params.Results.verbose;
no_mat_inc = params.Results.no_mat_inc;


% Check if X is path to mat file on disk
%   X_mat_flag is a flag that keeps track of if X is an array or path to
%   a mat file on disk. In the latter case, X_mat will be a matfile that
%   can be used to access elements of the mat file.
if isa(X, 'char') || isa(X, 'string')
    X_mat_flag = true;
    X_mat = matfile(X, 'Writable', false);
else
    X_mat_flag = false;
end

%% Initialize cores, sampling probabilities and sampled cores

if X_mat_flag
    sz = size(X_mat, 'Y');
    N = length(sz);
    col_cell = cell(1,N);
    for n = 1:N
        col_cell{n} = ':';
    end
    
    % If value for no_mat_inc is provided, make sure it is a properly shaped
    % vector.
    if no_mat_inc(1)
        if ~(size(no_mat_inc,1)==1 && size(no_mat_inc,2)==N)
            no_mat_inc = no_mat_inc(1)*ones(1,N);
        end
    end
else
    sz = size(X);
    N = length(sz);
end
cores = initialize_cores(sz, ranks);

sampling_probs = cell(1, N);
for n = 2:N
    U = col(classical_mode_unfolding(cores{n}, 2));
    sampling_probs{n} = sum(U.^2, 2)/size(U, 2);
end
core_samples = cell(1, N);

slow_idx = cell(1,N);
sz_shifted = [1 sz(1:end-1)];
idx_prod = cumprod(sz_shifted);
for n = 1:N
    J = embedding_dims(n);
    samples_lin_idx_2 = prod(sz_shifted(1:n))*(0:sz(n)-1).';
    slow_idx{n} = repelem(samples_lin_idx_2, J, 1);
end

%% Main loop
% Iterate until convergence, for a maximum of maxiters iterations

if ~resample
    J = embedding_dims(1); % Always use same embedding dim
    samples = nan(J, N);
    
    for m = 2:N-1
        samples(:, m) = randsample(sz(m), J, true, sampling_probs{m});
        core_samples{m} = cores{m}(:, samples(:,m), :);
    end
end

er_old = Inf;
for it = 1:maxiters
    for n = 1:N
        
        % Construct sketch and sample cores
        if resample
            % Resample all cores, except nth which will be updated
            J = embedding_dims(n);
            samples = nan(J, N);
            for m = 1:N
                if m ~= n
                    samples(:, m) = randsample(sz(m), J, true, sampling_probs{m});
                    core_samples{m} = cores{m}(:, samples(:,m), :);
                end
            end
        else
            % Only resample the core that was updated in last iteration
            m = mod(n-2,N)+1;
            samples(:, m) = randsample(sz(m), J, true, sampling_probs{m});
            core_samples{m} = cores{m}(:, samples(:,m), :);
        end
        
        % Compute the row rescaling factors
        rescaling = ones(J, 1);
        for m = 1:N
            if m ~= n
                rescaling = rescaling ./ sqrt(sampling_probs{m}(samples(:, m)));
            end
            rescaling = rescaling ./ sqrt(J);
        end
        
        % Construct sketched design matrix
        idx = [n+1:N 1:n-1]; % Order in which to multiply cores
        G_sketch = permute(core_samples{idx(1)}, [1 3 2]);
        for m = 2:N-1
            permuted_core = permute(core_samples{idx(m)}, [1 3 2]);
            G_sketch = mtimesx(G_sketch, permuted_core);
        end
        G_sketch = permute(G_sketch, [3 2 1]);
        G_sketch = reshape(G_sketch, J, numel(G_sketch)/J);
        G_sketch = rescaling .* G_sketch;
        
        % Construct sketched right hand side
        if X_mat_flag
            % doing trick below since matfile arrays don't take linear
            % indexes
            slice_arg = col_cell;
            inc_pts = linspace(0, sz(n), no_mat_inc(n)+1);
            Xn_sketch = zeros(J, sz(n));
            for m = 1:no_mat_inc(n)
                
                
                slice_arg{n} = inc_pts(m)+1:inc_pts(m+1);
                df = inc_pts(m+1)-inc_pts(m);
                sz_slice = sz;
                sz_slice(n) = df;
                sz_slice_shifted = [1 sz_slice(1:end-1)];
                idx_slice_prod = cumprod(sz_slice_shifted);

                %samples_lin_idx = sub2ind(sz([idx n]), [repmat(samples(:, idx), df, 1) repelem((1:df).', J, 1)]);
                samples_lin_idx_1 = 1 + (samples(:, idx)-1) * idx_slice_prod(idx).';
                samples_lin_idx_2 = idx_slice_prod(n)*(0:df-1).';
                samples_lin_idx = repmat(samples_lin_idx_1, df, 1) + repelem(samples_lin_idx_2, J, 1);
                X_slice = X_mat.Y(slice_arg{:});
                Xn_sketch(:, inc_pts(m)+1:inc_pts(m+1)) = reshape(X_slice(samples_lin_idx), J, df);
            end
        else
            % X array in RAM -- use linear indexing
            samples_lin_idx_1 = 1 + (samples(:, idx)-1) * idx_prod(idx).';
            samples_lin_idx = repmat(samples_lin_idx_1, sz(n), 1) + slow_idx{n};
            X_sampled = X(samples_lin_idx);
            Xn_sketch = reshape(X_sampled, J, sz(n));
        end
        
        
        %Xn_sketch = reshape(X_sampled, sz(n), J);
        %Xn_sketch = permute(Xn_sketch, [2 1]);
        Xn_sketch = rescaling .* Xn_sketch;
        
        % Below is old code for constructing sketched RHS, which is slower
        % than the above block.
        %{
        Xn = permute(mode_unfolding(X, n), [2 1]);
        samples_prod = 1 + (samples(:, idx)-1) * [1 cumprod(sz(idx(1:end-1)))].'; 
        Xn_sketch = Xn(samples_prod, :);      
        if isa(Xn_sketch, 'sptensor')
            Xn_sketch = sparse(Xn_sketch.subs(:,1), Xn_sketch.subs(:,2), Xn_sketch.vals, size(Xn_sketch,1), size(Xn_sketch,2));
        end
        %}
        
        % Solve sketched LS problem and update core
        Z = (G_sketch \ Xn_sketch).';
        cores{n} = classical_mode_folding(Z, 2, size(cores{n}));
        
        % Update sampling distribution for core
        U = col(classical_mode_unfolding(cores{n}, 2));
        sampling_probs{n} = sum(U.^2, 2)/size(U, 2);
    end
    
    if tol > 0
        % Compute full tensor corresponding to cores
        Y = cores_2_tensor(cores);

        % Compute current relative error
        if X_mat_flag
            XX = X_mat.Y;
            er = norm(XX(:)-Y(:))/norm(XX(:));
        else
            er = norm(X(:)-Y(:))/norm(X(:));
        end
        
        if verbose
            fprintf('\tRelative error after iteration %d: %.8f\n', it, er);
        end

        % Break if change in relative error below threshold
        if abs(er - er_old) < tol
            if verbose
                fprintf('\tRelative error change below tol; terminating...\n');
            end
            break
        end

        % Update old error
        er_old = er;
    else
        if verbose
            fprintf('\tIteration %d complete\n', it);
        end
    end
    
end

end