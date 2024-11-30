clear; clc; close all;
%----------------------
addNeedPaths; % add paths and toolbox
%--------------------------

% Parameters of energy minimization (mesh deformation)
parameters.grid_size = 40;
parameters.line_align = 5;
parameters.perspective = 50;
parameters.projective = 5;
parameters.saliency = 5;
parameters.line_threshold = 50;

%------------------------
% Images to stitch
%-----------------------
pathname = strcat('..\MultiImage\Imgs\0\');
outpath = strcat(pathname, 'results\');
imgs_format = '*.jpg';
dir_folder = dir(strcat(pathname, imgs_format));
num_images = length(dir_folder);

if ~exist(outpath,'dir'); mkdir(outpath); end

% Start with first image as reference
current_result = im2double(imread(fullfile(pathname, dir_folder(1).name)));

% Sequentially stitch remaining images
for i = 2:num_images
    fprintf('Stitching image %d of %d\n', i, num_images);
    
    % Current image to stitch
    next_image = im2double(imread(fullfile(pathname, dir_folder(i).name)));
    
    % Resolution/grid-size for the mapping function
    C1 = ceil(size(current_result,1)/parameters.grid_size);
    C2 = ceil(size(current_result,2)/parameters.grid_size);
    
    % SIFT matching
    [pts1, pts2] = siftMatch(current_result, next_image);
    [matches_1, matches_2] = multiSample_APAP(pts1, pts2);
    
    % Line matching
    % Save temporary images for line matching
    temp_ref = fullfile(outpath, 'temp_ref.jpg');
    temp_next = fullfile(outpath, 'temp_next.jpg');
    imwrite(current_result, temp_ref);
    imwrite(next_image, temp_next);
    [line_match1, line_match2] = twoLineMatch(temp_ref, temp_next, matches_1, matches_2, parameters);
    
    % Calculate homography
    [h, ~, T1, T2] = calcHomoPointLine(matches_1, matches_2, line_match1, line_match2);
    pts_line_H = T2\(h*T1);
    
    % Generate mesh grid
    [X, Y] = meshgrid(linspace(1,size(current_result,2),C2+1), linspace(1,size(current_result,1),C1+1));
    Mv = [X(:), Y(:)];
    init_H = pts_line_H;
    init_H = init_H./(init_H(end));
    theta = atan2(-init_H(6), -init_H(3));
    
    % Calculate energy terms
    [lines_vs, lines_us, lines_ue] = generateUV(current_result, next_image, init_H, theta, C1, C2);
    nor_vec_v = [init_H(2)*init_H(6)-init_H(5)*init_H(3), init_H(4)*init_H(3)-init_H(1)*init_H(6)];
    nor_vec_v = nor_vec_v./norm(nor_vec_v);
    
    sparse_v = energyLineV(current_result, C1, C2, lines_vs, nor_vec_v);
    [sparse_us, sparse_ue] = energyLineU(current_result, C1, C2, lines_us, lines_ue, init_H);
    [sparse_align, psMatch] = energyAlign(current_result, C1, C2, matches_1, matches_2);
    [sparse_line_align, cMatch] = energyLineAlign(current_result, C1, C2, line_match1, line_match2);
    [sa_lines, sl_lines] = linesDetect(temp_ref, current_result, C1, C2);
    sparse_line = energyLineSegment(current_result, sa_lines, sl_lines, init_H, C1, C2);
    
    % Solve optimization
    zero_len = size(sparse_us,1)+size(sparse_v,1)+size(sparse_ue,1)+size(sparse_line,1);
    warp_hv = init_H*[Mv'; ones(1,length(Mv))];
    warp_hv = warp_hv(1:2,:)./repmat(warp_hv(3,:),2,1);
    init_V = warp_hv(:);
    
    Matrix_A = [sparse_align; sqrt(parameters.line_align).*sparse_line_align; 
                sqrt(parameters.perspective).*sparse_us; sqrt(parameters.perspective).*sparse_v;
                sqrt(parameters.projective).*sparse_ue; sqrt(parameters.saliency).*sparse_line];
    m_x = [psMatch; sqrt(parameters.line_align).*cMatch; zeros(zero_len,1)];
    
    [V_star, ~, ~, ~] = lsqr(Matrix_A, m_x, 1e-8, 5000, [], [], init_V);
    optimized_V = vec2mat_(V_star,2);
    
    % Warp and blend
    wX = reshape(optimized_V(:,1), C1+1, C2+1);
    wY = reshape(optimized_V(:,2), C1+1, C2+1);
    warped_img1 = meshmap_warp2homo(current_result, X, Y, wX, wY);
    
    % Calculate canvas size and create blending
    off = ceil([1 - min([1 optimized_V(:,1)']) + 1; 1 - min([1 optimized_V(:,2)']) + 1]);
    cw = max([ceil(optimized_V(:,1))', size(next_image,2)])+off(1)-1;
    ch = max([ceil(optimized_V(:,2))', size(next_image,1)])+off(2)-1;
    
    img1Homo = zeros(ch,cw,3); img2Homo = zeros(ch,cw,3);
    img1Homo(floor(min(optimized_V(:,2)))+off(2)-1:floor(min(optimized_V(:,2)))+off(2)-2+size(warped_img1,1),...
        floor(min(optimized_V(:,1)))+off(1)-1:floor(min(optimized_V(:,1)))+off(1)-2+size(warped_img1,2), :) = warped_img1;
    img2Homo(off(2):(off(2)+size(next_image,1)-1),off(1):(off(1)+size(next_image,2)-1),:) = next_image;
    
    % Update current result for next iteration
    current_result = imageBlending(img1Homo, img2Homo, 'linear');
    
    % Save intermediate result
    imwrite(current_result, [outpath sprintf('step_%d.jpg', i)]);
end

% Save final result
imwrite(current_result, [outpath 'final_panorama.jpg']);
fprintf('Multi-image stitching completed!\n');