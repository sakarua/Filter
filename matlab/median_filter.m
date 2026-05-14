%% 读取图像
originalImage = imread('test_img.bmp');
figure;
%% 显示原图
subplot(1, 3, 1);
imshow(originalImage);
title('原图像');
%% 灰度化 
grayImage = rgb2gray(originalImage);
%% 图像尺寸
[img_height, img_width] = size(grayImage); 
medianImage = zeros(img_height, img_width);
%% 定义参数
windowSize = 3;  % 窗口大小，奇数
%% 遍历像素 计算窗口均值
halfWindowSize = floor(windowSize / 2);
for i = 1:img_height
    for j = 1:img_width
        % 窗口边界
        r1 = max(i - halfWindowSize, 1);    %窗口上边界
        r2 = min(i + halfWindowSize, img_height);%窗口下边界
        c1 = max(j - halfWindowSize, 1);%窗口左边界
        c2 = min(j + halfWindowSize, img_width);%窗口右边界
        
        % 提取窗口
        window = grayImage(r1:r2, c1:c2);
        
        % 计算窗口内的中值
        localmedian = median(window(:));
        
        medianImage(i,j) = localmedian;
    end
end
%% 无符号8bit
medianImage = uint8(medianImage);   
%% 将原图像转换为二值图像
binarizedImage = imbinarize(grayImage);

% 显示原图和处理后的图像
subplot(1, 3, 2);
imshow(grayImage);
title('灰度化图像');

subplot(1, 3, 3);
imshow(medianImage);
title('中值滤波图像');
