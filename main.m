@import Foundation; // for -[NSDictionary description]
@import ImageIO;
#include <sysexits.h> // for EX_USAGE

static void printProperties(CFDictionaryRef properties) {
	if (properties == NULL) {
		printf("Properties: NULL\n");
		return;
	}
	
	// Use Objective-C description because CFCopyDescription() format looks terrible.
	@autoreleasepool {
		NSString *description = [(__bridge NSDictionary *)properties description];
		const char *cString = [description UTF8String];
		if (cString == NULL) {
			cString = "Not UTF8";
		}
		printf("Properties: %s\n", cString);
	}
	
	CFRelease(properties);
}

static bool printImage(CGImageRef image) {
	CGBitmapInfo bitmap = CGImageGetBitmapInfo(image);
	CGImageByteOrderInfo byteOrder = bitmap & kCGBitmapByteOrderMask;
	if (byteOrder != kCGBitmapByteOrderDefault) {
		fprintf(stderr, "jixel does not support %u byte order. Please file a bug if you need this.\n", byteOrder);
		return false;
	}
	
	bool hasAlpha = true;
	CGImageAlphaInfo alpha = CGImageGetAlphaInfo(image);
	switch (alpha) {
		case kCGImageAlphaNone:
			hasAlpha = false;
			break;
		case kCGImageAlphaPremultipliedLast:
			break;
		case kCGImageAlphaPremultipliedFirst:
			break;
		case kCGImageAlphaLast:
			break;
		case kCGImageAlphaFirst:
			break;
		case kCGImageAlphaNoneSkipLast:
			break;
		case kCGImageAlphaNoneSkipFirst:
			break;
		case kCGImageAlphaOnly: {
			fprintf(stderr, "jixel does not support image masks. Please file a bug if you need this.\n");
			return false;
		}
		default: {
			fprintf(stderr, "CGImageGetAlphaInfo:%i \n", alpha);
			return false;
		}
	}
	
	CGColorSpaceRef colorSpace = CGImageGetColorSpace(image);
	if (colorSpace == NULL) {
		fprintf(stderr, "CGImageGetColorSpace NULL, image mask.\n");
		return false;
	}
	CGColorSpaceModel model = CGColorSpaceGetModel(colorSpace);
	switch (model) {
		case kCGColorSpaceModelMonochrome:
			if (hasAlpha) {
				fprintf(stderr, "kCGColorSpaceModelMonochrome %u\n", alpha);
				return false;
			}
			break;
			
		case kCGColorSpaceModelRGB:
			if (!hasAlpha) {
				fprintf(stderr, "kCGColorSpaceModelRGB kCGImageAlphaNone\n");
				return false;
			}
			break;
			
		case kCGColorSpaceModelCMYK:
			if (hasAlpha) {
				fprintf(stderr, "kCGColorSpaceModelCMYK %u\n", alpha);
				return false;
			}
			break;
			
		default: {
			fprintf(stderr, "CGColorSpaceGetModel %i\n", model);
			return false;
		}
	}
	
	bool floatComponents = (bitmap & kCGBitmapFloatInfoMask) == kCGBitmapFloatComponents;
	size_t bitsPerComponent = CGImageGetBitsPerComponent(image);
	switch (bitsPerComponent) {
		case 5: {
			fprintf(stderr, "jixel does not support 5 bits per component RGB. Please file a bug if you need this.\n");
			return false;
		}
		case 8:
			if (floatComponents) {
				fprintf(stderr, "Float 8 bits per component\n");
				return false;
			}
			break;
		case 16:
			if (floatComponents) {
				fprintf(stderr, "Float 16 bits per component\n");
				return false;
			}
			break;
		case 32:
			if (!floatComponents) {
				fprintf(stderr, "Non-float 32 bits per component\n");
				return false;
			}
			break;
		default: {
			fprintf(stderr, "CGImageGetBitsPerComponent:%lu\n", bitsPerComponent);
			return false;
		}
	}
	
	size_t bitsPerPixel = CGImageGetBitsPerPixel(image);
	if (model == kCGColorSpaceModelMonochrome) {
		if (bitsPerPixel != bitsPerComponent) {
			fprintf(stderr, "CGImageGetBitsPerComponent:%lu CGImageGetBitsPerPixel:%lu\n", bitsPerComponent, bitsPerPixel);
			return false;
		}
	} else {
		if (bitsPerPixel != bitsPerComponent * 4) {
			fprintf(stderr, "CGImageGetBitsPerComponent:%lu CGImageGetBitsPerPixel:%lu\n", bitsPerComponent, bitsPerPixel);
			return false;
		}
	}
	
	size_t width = CGImageGetWidth(image);
	if (width == 0) {
		fprintf(stderr, "CGImageGetWidth 0\n");
		return false;
	}
	size_t height = CGImageGetHeight(image);
	if (height == 0) {
		fprintf(stderr, "CGImageGetHeight 0\n");
		return false;
	}
	
	size_t bytesPerRow = CGImageGetBytesPerRow(image);
	if (bytesPerRow == 0) {
		fprintf(stderr, "CGImageGetBytesPerRow 0\n");
		return false;
	}
	size_t bytesPerPixel = bitsPerPixel / 8;
	if (bytesPerPixel * width != bytesPerRow) {
		fprintf(stderr, "CGImageGetBitsPerPixel:%lu CGImageGetWidth:%lu CGImageGetBytesPerRow:%lu\n", bitsPerPixel, width, bytesPerRow);
		return false;
	}
	
	CGDataProviderRef dataProvider = CGImageGetDataProvider(image);
	if (dataProvider == NULL) {
		fprintf(stderr, "CGImageGetDataProvider NULL\n");
		return false;
	}
	CFDataRef data = CGDataProviderCopyData(dataProvider);
	if (data == NULL) {
		fprintf(stderr, "CGDataProviderCopyData NULL\n");
		return false;
	}
	CFIndex length = CFDataGetLength(data);
	if (length <= 0) {
		fprintf(stderr, "CFDataGetLength %li\n", length);
		CFRelease(data);
		return false;
	}
	if (bytesPerRow * height != (size_t)length) {
		fprintf(stderr, "CGImageGetBytesPerRow:%lu CGImageGetHeight:%lu CFDataGetLength:%li\n", bytesPerRow, height, length);
		CFRelease(data);
		return false;
	}
	const UInt8 *bytes = CFDataGetBytePtr(data);
	
	for (size_t column = 0; column < width; column++) {
		for (size_t row = 0; row < height; row++) {
			// 5 digit dimensions minimum for formatting.
			// This should be enough, but the fields will automatically expand if there are more digits.
			printf("\nX:%-5lu Y:%-5lu ", column, row);  
			
			const UInt8 *pixel = bytes + (row * bytesPerRow);
			if (bitsPerComponent == 8) { // Values 0 - 255, 3 digits
				if (model == kCGColorSpaceModelMonochrome) {
					printf("G:%-3u", *pixel);
				} else if (model == kCGColorSpaceModelCMYK) {
					printf("C:%-3u M:%-3u Y:%-3u K:%-3u", pixel[0], pixel[1], pixel[2], pixel[3]);
				} else if (model == kCGColorSpaceModelRGB) {
					if (alpha == kCGImageAlphaPremultipliedLast || alpha == kCGImageAlphaLast) {
						printf("R:%-3u G:%-3u B:%-3u A:%-3u", pixel[0], pixel[1], pixel[2], pixel[3]);
					} else if (alpha == kCGImageAlphaPremultipliedFirst || alpha == kCGImageAlphaFirst) {
						printf("R:%-3u G:%-3u B:%-3u A:%-3u", pixel[1], pixel[2], pixel[3], pixel[0]);
					} else if (alpha == kCGImageAlphaNoneSkipLast) {
						printf("R:%-3u G:%-3u B:%-3u", pixel[0], pixel[1], pixel[2]);
					} else if (alpha == kCGImageAlphaNoneSkipFirst) {
						printf("R:%-3u G:%-3u B:%-3u", pixel[1], pixel[2], pixel[3]);
					}
				}
			} else if (bitsPerComponent == 16) { // Values 0 - 65535, 5 digits
				const UInt16 *components = (const UInt16 *)pixel;
				if (model == kCGColorSpaceModelMonochrome) {
					printf("G:%-5u", *components);
				} else if (model == kCGColorSpaceModelCMYK) {
					printf("C:%-5u M:%-5u Y:%-5u K:%-5u", components[0], components[1], components[2], components[3]);
				} else if (model == kCGColorSpaceModelRGB) {
					if (alpha == kCGImageAlphaPremultipliedLast || alpha == kCGImageAlphaLast) {
						printf("R:%-5u G:%-5u B:%-5u A:%-5u", components[0], components[1], components[2], components[3]);
					} else if (alpha == kCGImageAlphaPremultipliedFirst || alpha == kCGImageAlphaFirst) {
						printf("R:%-5u G:%-5u B:%-5u A:%-5u", components[1], components[2], components[3], components[0]);
					} else if (alpha == kCGImageAlphaNoneSkipLast) {
						printf("R:%-5u G:%-5u B:%-5u", components[0], components[1], components[2]);
					} else if (alpha == kCGImageAlphaNoneSkipFirst) {
						printf("R:%-5u G:%-5u B:%-5u", components[1], components[2], components[3]);
					}
				}
			} else if (bitsPerComponent == 32) {
				const Float32 *components = (const Float32 *)pixel;
				if (model == kCGColorSpaceModelMonochrome) {
					printf("G:%f", *components);
				} else if (model == kCGColorSpaceModelCMYK) {
					printf("C:%f M:%f Y:%f K:%f", components[0], components[1], components[2], components[3]);
				} else if (model == kCGColorSpaceModelRGB) {
					if (alpha == kCGImageAlphaPremultipliedLast || alpha == kCGImageAlphaLast) {
						printf("R:%f G:%f B:%f A:%f", components[0], components[1], components[2], components[3]);
					} else if (alpha == kCGImageAlphaPremultipliedFirst || alpha == kCGImageAlphaFirst) {
						printf("R:%f G:%f B:%f A:%f", components[1], components[2], components[3], components[0]);
					} else if (alpha == kCGImageAlphaNoneSkipLast) {
						printf("R:%f G:%f B:%f", components[0], components[1], components[2]);
					} else if (alpha == kCGImageAlphaNoneSkipFirst) {
						printf("R:%f G:%f B:%f", components[1], components[2], components[3]);
					}
				}
			}
		}
		bytes += bytesPerPixel;
	}
	printf("\n");
	
	CFRelease(data);
	
	return true;
}

static int printSource(CGImageSourceRef source) {
	size_t count = CGImageSourceGetCount(source);
	if (count == 0) {
		fprintf(stderr, "CGImageSourceGetCount 0\n");
		return EXIT_FAILURE;
	}
	
	CFIndex numberOfValues = 2;
	CFStringRef keys[numberOfValues];
	CFBooleanRef values[numberOfValues];
	keys[0] = kCGImageSourceShouldAllowFloat;
	keys[1] = kCGImageSourceShouldCacheImmediately;
	values[0] = kCFBooleanTrue;
	values[1] = kCFBooleanTrue;
	CFDictionaryRef options = CFDictionaryCreate(NULL, (const void **)keys, (const void **)values, numberOfValues, &kCFCopyStringDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	
	for (size_t i = 0; i < count; i++) {
		printf("\nIndex: %lu\n", i);
		
		CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(source, i, options);
		printProperties(properties);
		
		CGImageRef image = CGImageSourceCreateImageAtIndex(source, i, options);
		if (image == NULL) {
			fprintf(stderr, "CGImageSourceCreateImageAtIndex NULL\n");
			CFRelease(options);
			return EXIT_FAILURE;
		}
		
		bool didPrint = printImage(image);
		CGImageRelease(image);
		if (!didPrint) {
			CFRelease(options);
			return EXIT_FAILURE;
		}
	}
	
	CFRelease(options);
	return EXIT_SUCCESS;
}

int main(int argc, const char *argv[]) {
	if (argc != 2) {
		printf("usage: jixel <path>\n");
		return EX_USAGE;
	}
	
	const char *path = argv[1];
	CFStringRef filePath = CFStringCreateWithCString(NULL, path, CFStringGetSystemEncoding());
	if (filePath == NULL) {
		fprintf(stderr, "CFStringCreateWithCString: %s\n", path);
		return EXIT_FAILURE;
	}
	CFURLRef url = CFURLCreateWithFileSystemPath(NULL, filePath, kCFURLPOSIXPathStyle, false);
	CFRelease(filePath);
	if (url == NULL) {
		fprintf(stderr, "CFURLCreateWithFileSystemPath: %s\n", path);
		return EXIT_FAILURE;
	}	
	CGImageSourceRef source = CGImageSourceCreateWithURL(url, NULL);
	CFRelease(url);
	if (source == NULL) {
		fprintf(stderr, "CGImageSourceCreateWithURL NULL\n");
		return EXIT_FAILURE;
	}
	
	CFStringRef type = CGImageSourceGetType(source);
	const char *cString;
	if (type == NULL) {
		cString = "NULL";
	} else {
		cString = CFStringGetCStringPtr(type, kCFStringEncodingUTF8);
		if (cString == NULL) {
			cString = "Not UTF8";
		}
	}
	printf("Type: %s\n", cString);
	
	CFDictionaryRef properties = CGImageSourceCopyProperties(source, NULL);
	printProperties(properties);
	
	int success = printSource(source);
	CFRelease(source);
	return success;
}
