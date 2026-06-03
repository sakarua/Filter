%% 读取图像
originalImage = imread('test_img.bmp');
figure;
%% 显示原图
subplot(1, 3, 1);
imshow(originalImage);
title('原图像');
%% 灰度化
% 提取 R, G, B 三通道并转换为 uint32 以防乘法溢出
R = uint32(originalImage(:, :, 1));
G = uint32(originalImage(:, :, 2));
B = uint32(originalImage(:, :, 3));

% 按照 RTL 逻辑进行加权求和
grayImage = bitsra(R*77 + G*150 + B*29, 8);

% 换回 uint8 类型，确保与后续处理兼容
grayImage = uint8(grayImage);
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

subplot(1, 3, 2);
imshow(rawCFA, []);
title('原始CFA数据');

subplot(1, 3, 3);
imshow(filteredCFA, []);
title('中值滤波后CFA');

%% 保存为TXT文件（十六进制格式）
% 获取尺寸
[img_height, img_width] = size(filteredCFA);

% 打开文件
fileID = fopen('median_filtered_raw.txt', 'w');

% 写入数据
for i = 1:img_height
    for j = 1:img_width
        % 获取像素值
        pixelValue = filteredCFA(i, j);
        
        % 根据数据类型决定输出格式
        if isa(pixelValue, 'uint16')
            % 16位数据：输出4位十六进制
            fprintf(fileID, '%04x', pixelValue);
        elseif isa(pixelValue, 'uint8')
            % 8位数据：输出2位十六进制
            fprintf(fileID, '%02x', pixelValue);
        else
            % double类型：先转为uint16再输出
            fprintf(fileID, '%04x', uint16(pixelValue));
        end
        
        % 每列之间加空格（可选，便于阅读）
        if j < img_width
            fprintf(fileID, ' ');
        end
    end
    % 每行结束后换行
    fprintf(fileID, '\n');
end

% 关闭文件
fclose(fileID);

fprintf('TXT文件已保存：median_filtered_raw.txt\n');
fprintf('图像尺寸：%d × %d\n', img_height, img_width);