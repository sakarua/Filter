clear; clc;

%% 参数设置（根据你的图像修改）
width = 480;
height = 640; 
windowSize = 3; % 中值滤波窗口大小

%% 直接读取 16bit 纯二进制灰度图
fileID = fopen('test_img.raw', 'r');
if fileID == -1
    error('无法打开 RAW 文件，请检查路径！');
end

% 'uint16=>uint16' 确保读取出来的数据直接就是 16位无符号整型 灰度值
rawData = fread(fileID, width * height, 'uint16=>uint16');
fclose(fileID);


% 恢复为二维灰度图像矩阵（转置是因为 MATLAB 是列优先）
grayImage = reshape(rawData, [width, height])';

%% 中值滤波处理
medianImage = zeros(height, width, 'uint16'); % 预分配内存，指定 uint16 类型
halfWindowSize = floor(windowSize / 2);

for i = 1:height
    for j = 1:width
        % 边界处理
        r1 = max(i - halfWindowSize, 1);
        r2 = min(i + halfWindowSize, height);
        c1 = max(j - halfWindowSize, 1);
        c2 = min(j + halfWindowSize, width);
        
        % 提取窗口并计算中值
        window = grayImage(r1:r2, c1:c2);
        medianImage(i,j) = median(window(:));
    end
end

%% 显示图像
figure;
subplot(1, 2, 1);
imshow(grayImage, []); % 使用 [] 自动拉伸 16bit 灰度对比度
title('原灰度图像');

subplot(1, 2, 2);
imshow(medianImage, []); 
title('中值滤波后图像');

%% 遍历每一个像素并写入到文件中
file_id = fopen('matlab_raw.txt', 'w+');

% 此时矩阵已经是标准的 2D 矩阵，直接双重循环保存
for row_index = 1:height
    for col_index = 1:width 
        % 以十六进制 (%04x) 格式写入 16bit 滤波后的像素值
        fprintf(file_id, '%04x', medianImage(row_index, col_index));
         fprintf(file_id, '\n'); % 每行结束后换行
    end
end
%% 关闭文件
fclose(file_id);
disp('处理完成，数据已成功保存！');