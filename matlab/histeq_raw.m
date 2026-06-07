clear; clc;
width = 480;   % RAW 图像宽度
height = 640;  % RAW 图像高度

% 读取纯二进制 16bit RAW 文件
fileID = fopen('test_img.raw', 'r');
if fileID == -1
    error('无法打开 RAW 文件！');
end
raw_data = fread(fileID, width * height, 'uint16=>uint16');
fclose(fileID);

% 恢复为二维矩阵并转置
raw_gray = reshape(raw_data, [width, height])';

counts = imhist(raw_gray, 65536);       % 统计直方图
cdf = cumsum(counts) / numel(raw_gray); % 累积分布函数
raw_eq = uint16(cdf(double(raw_gray)+1) * 65535);  % 映射

%% 输出比较
% 显示原图和处理后的图像
subplot(1, 2, 1);
imshow(raw_gray, []);
title('灰度化图像');

subplot(1, 2, 2);
imshow(raw_eq, []);
title('直方图均衡化图像');