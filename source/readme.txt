这里是编译的源码，编译IOS方法
1、打开/build-mac/mailcore2.xcodeproj
2、target选择 static mailcore2 ios
3、分别用真机和模拟器编译(command+B)编译项目
4、在/Users/xxx/Library/Developer/Xcode/DerivedData/mailcore2.*/Build/Products下执行 命令合并真机和模拟器的静态文件(libMailCore-ios.a)

合并命令
lipo -create \
  /path/to/Debug-iphoneos/libXXX.a \
  /path/to/Debug-iphonesimulator/libXXX.a \
  -output /path/to/output/libXXX.a
验证合并结果
lipo -info /path/to/output/libXXX.a


5、把合并好的libXXX.a 和include(包含头文件)放到一个文件夹下面 就可以手动集成到项目了
