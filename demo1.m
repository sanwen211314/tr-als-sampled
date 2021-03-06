% This is just a test script used to quickly compare different methods. I
% may eventually remove this entirely...

sz = [100 100 100];
ranks = 10*ones(size(sz));
noise = 1e-1;
target_acc = 1.2;
no_trials = 10;

X = generate_low_rank_tensor(sz, ranks+0, noise, 'large_elem', 20);

%% TR-ALS

no_it = 30;

tic; cores1 = tr_als(X, ranks, 'tol', 0, 'maxiters', no_it, 'verbose', true); time_1 = toc;
Y = cores_2_tensor(cores1);
acc_1 = norm(Y(:) - X(:))/norm(X(:));
fprintf('TR-ALS accuracy is %.2e\n', acc_1)


%% TR-ALS-Sampled
J = 2*ranks(1)^2;
J_inc = 1000;
time_2 = [];
acc_2 = [];
while true
    tic; 
    cores2 = tr_als_sampled(X, ranks, J*ones(size(sz)), 'tol', 0, 'maxiters', no_it, 'resample', true, 'verbose', true); 
    time_2 = [time_2; toc];
    Y = cores_2_tensor(cores2);
    acc_2 = [acc_2; norm(Y(:)-X(:))/norm(X(:))];
    fprintf('\tAccuracy for TR-ALS-Sampled is %.2e\n', acc_2(end));
    if acc_2(end)/acc_1 < target_acc
        fprintf('\tTarget accuracy reached; breaking...\n');
        break
    end
    J = J + J_inc;
end

%% TR-ALS-Sampled from disk
% J = 2*ranks(1)^2;
% J_inc = 1000;
% time_2_disk = [];
% acc_2_disk = [];
% X_mat_name = 'tensor.mat';
% Y = X;
% save(X_mat_name, 'Y', '-v7.3');
% while true
%     tic; 
%     cores2 = tr_als_sampled(X_mat_name, ranks, J*ones(size(sz)), 'tol', 0, 'maxiters', no_it, 'resample', true, 'verbose', true, 'no_mat_inc', 10); 
%     time_2_disk = [time_2_disk; toc];
%     Y = cores_2_tensor(cores2);
%     acc_2_disk = [acc_2_disk; norm(Y(:)-X(:))/norm(X(:))];
%     fprintf('\tAccuracy for TR-ALS-Sampled is %.2e\n', acc_2_disk(end));
%     if acc_2_disk(end)/acc_1 < target_acc
%         fprintf('\tTarget accuracy reached; breaking...\n');
%         break
%     end
%     J = J + J_inc;
% end

%% Projected TR-ALS (Yuan et al., 2019)
K = 10;
K_inc = 5;
time_3 = [];
acc_3 = [];
while true
    tic; 
    cores3 = rtr_als(X, ranks, K*ones(size(sz)), 'tol', 0, 'maxiters', no_it, 'verbose', true);
    time_3 = [time_3; toc];
    Y = cores_2_tensor(cores3);
    acc_3 = [acc_3; norm(Y(:)-X(:))/norm(X(:))];
    fprintf('\tAccuracy for rTRD is %.2e\n', acc_3(end));
    if acc_3(end)/acc_1 < target_acc
        fprintf('\tTarget accuracy reached; breaking...\n');
        break
    end
    K = K + K_inc;
end

%% Randomized TR-SVD (Ahmadi-Asl et al., 2020)
svd_ranks = ranks;
oversamp = 50;
tic;
cores4 = tr_svd_rand(X, svd_ranks, oversamp);
time_4 = toc;
Y = cores_2_tensor(cores4);
acc_4 = norm(Y(:) - X(:))/norm(X(:));
