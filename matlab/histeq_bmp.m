clear; clc;
bmp_img = imread('test_img.bmp');

% 如果是彩色 RGB 图像，先转为单通道灰度图
if size(bmp_img, 3) == 3
    R = uint32(bmp_img(:, :, 1));
    G = uint32(bmp_img(:, :, 2));
    B = uint32(bmp_img(:, :, 3));
    bmp_gray = uint8(bitsra(R*77 + G*150 + B*29, 8));
else
    bmp_gray = bmp_img;
end

% 对 8位图像进行直方图均衡化
% histeq 默认将 8位图映射到 256 个灰度级
bmp_eq = histeq(bmp_gray);

% 显示原图和处理后的图像
subplot(1, 3, 1);
imshow(bmp_img);
title('原图像');

subplot(1, 3, 2);
imshow(bmp_gray);
title('灰度化图像');

subplot(1, 3, 3);
imshow(bmp_eq, []);
title('直方图均衡化图像');