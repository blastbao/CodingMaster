;只有一个段，从0x7c00开始
section Initial vstart=0x7c00

;程序开始前的设置，先把段寄存器都置为0，后续所有地址都是相对0x00000的偏移
ZeroTheSegmentRegister:
  xor ax, ax ; 置零
  mov ds, ax ; 置零
  mov es, ax ; 置零
  mov ss, ax ; 置零

; 栈空间位于 0x7c00 及往前的空间，栈顶在 0x7c00 
;
; MBR 本身也是程序，是程序就要用到栈，栈也是在内存中的，MBRR 虽然本身只有 512 宇节，
; 但还要为其所用的栈分配点空间，所以其实际所用的内存空间要大于 512 字节，估计 1KB 内存够用了。
SetupTheStackPointer:
  mov sp, 0x7c00

Start:
  ; 打印 'Start Booting!'
  mov si, BootLoaderStart
  call PrintString

; 查看是否支持拓展 int 13h
; https://en.wikipedia.org/wiki/INT_13H
CheckExtInt13:
  mov ah, 0x41    ; 功能号 0x41 就是询问磁盘扩展读功能
  mov bx, 0x55aa  ; 入口参数，固定 0x55aa
  mov dl, 0x80    ; 要测试的驱动器，0x80 是第一块，0x81 是第二块，...
  int 0x13        ; 以软件中断形式调用，由此看来，BIOS 中肯定有中断向量表。
  cmp bx, 0xaa55  ; 如果存在扩展 13H 功能，则 bx == 0xaa55 
  mov byte [ShitHappens+0x06], 0x31
  jnz BootLoaderEnd ; 如果不支持，报错


; 寻找 MBR 分区表中的活动分区，看分区项第一个字节是否为 0x80 ，最多 4 个分区
;
; 位于 MBR 中的主 boot loader 是一个 512 字节的镜像，其中不仅包含了 bootload 程序代码，还包含了一个小的分区表。
; 最初的 446 字节是主 boot loader，它里面就包含有可执行代码以及错误消息文本。
; 接下来的 64 字节是分区表，其中包含有四个分区的各自的记录（一个分区占 16 字节）。
; MBR 通过特殊数字 0xAA55 作为两个字节的结束标志，0x55AA 同时也是 MBR 有效的校验确认。
;
; 主boot loader的工作是寻找并加载次 boot loader 。
; 它通过分析分区表，找出激活分区来完成这个任务，当它找到一个激活分区时，它将继续扫描剩下的分区表中的分区，以便确认他们都是未激活的。
; 确认完毕后，激活分区的启动记录从设备中被读到 RAM ，并被执行。
;
; “主引导记录” 只有512个字节，放不了太多东西。
; 它的主要作用是，告诉计算机到硬盘的哪一个位置去找操作系统。
; 
; 主引导记录由三个部分组成：
;   第1-446字节：调用操作系统的机器码。
;   第447-510字节：分区表（Partition table）。
;   第511-512字节：主引导记录签名（0x55和0xAA）。
; 
; 其中，第二部分 ”分区表” 的作用，是将硬盘分成若干个区。
;
;
; ### 分区表 ###
;
; 硬盘分区有很多好处。
; 考虑到每个区可以安装不同的操作系统，”主引导记录” 因此必须知道将控制权转交给哪个区。
; 分区表的长度只有 64 个字节，里面又分成四项，每项 16 个字节。
; 所以，一个硬盘最多只能分四个一级分区，又叫做“主分区”。
;
; 每个主分区的 16 个字节，由 6 个部分组成：
;  第 1 个字节：如果为 0x80 ，就表示该主分区是激活分区，控制权要转交给这个分区。四个主分区里面只能有一个是激活的。
;  第 2-4 个字节：主分区第一个扇区的物理位置（柱面、磁头、扇区号等等）。
;  第 5 个字节：主分区类型。
;  第 6-8 个字节：该主分区最后一个扇区的物理位置。
;  第 9-12 字节：该主分区第一个扇区的逻辑地址。
;  第 13-16 字节：主分区的扇区总数。
; 
; 最后的四个字节（”主分区的扇区总数”），决定了这个主分区的长度。也就是说，一个主分区的扇区总数最多不超过 2 的 32 次方。
; 如果每个扇区为 512 个字节，就意味着单个分区最大不超过 2TB 。再考虑到扇区的逻辑地址也是 32 位，所以单个硬盘可利用的空间最大也不超过 2TB 。
;
; 如果想使用更大的硬盘，只有2个方法：
;  一是提高每个扇区的字节数，
;  二是增加扇区总数。
; 
; MBR：第一个可开机设备的第一个扇区内的主引导分区块，内包含引导加载程序
; 引导加载程序（Boot loader）: 一支可读取内核文件来执行的软件
; 内核文件：开始操作系统的功能
;
;
SeekTheActivePartition:
  ; 分区表位于 0x7c00+446 = 0x7c00+0x1be = 0x7dbe 的位置，使用 di 作为基地址
  mov di, 0x7dbe     ; 分区表基址
  mov cx, 4          ; 最多 4 个分区，loop 最多 4 次
  isActivePartition:
    mov bl, [di]     ; 取分区表首字节
    cmp bl, 0x80     ; 检查是否 0x80 
    je ActivePartitionFound ; 如果是 0x80 ，说明找到激活分区了，跳转
    add di, 16              ; 如果非 0x80 ，说明没找到，则继续寻找下一个分区项，si+16
    loop isActivePartition
  ActivePartitionNotFound:  ; 如果连续 4 次检查均失败，报错退出
    mov byte [ShitHappens+0x06], 0x32 ; 设置错误码 0x32 = 50 
    jmp BootLoaderEnd                 ; 退出

; 找到活动分区后，di 目前就是活动分区项的首地址
;
; 把激活分区的数据从磁盘加载到内存 0x7e00 处
ActivePartitionFound:
  ; 打印字符串 'Get Partition!'
  mov si, PartitionFound
  call PrintString

  ; ebx 保存活动分区的起始地址
  mov ebx, [di+8]                 ; 
  mov dword [BlockLow], ebx       ; 起始扇区

  ;目标内存起始地址
  mov word [BufferOffset], 0x7e00 ; 内存地址: 把磁盘数据加载到地址 0x7e00 处
  mov byte [BlockCount], 1        ; 扇区数目: 从 BlockLow 开始加载共 n 个扇区

  ;读取第一个扇区
  call ReadDisk

GetFirstFat:
  mov di, 0x7e00
  ;ebx目前为保留扇区数
  xor ebx, ebx
  mov bx, [di+0x0e]
  ;FirstFat起始扇区号=隐藏扇区+保留扇区
  mov eax, [di+0x1c]
  add ebx, eax

;获取数据区起始区扇区号
GetDataAreaBase:
  mov eax, [di+0x24]
  xor cx, cx
  mov cl, [di+0x10]
  AddFatSize:
    add ebx, eax
    loop AddFatSize

;读取数据区8个扇区/1个簇
ReadRootDirectory:
  mov [BlockLow], ebx
  mov word [BufferOffset], 0x8000
  mov di, 0x8000
  mov byte [BlockCount], 8
  call ReadDisk
  mov byte [ShitHappens+0x06], 0x34

SeekTheInitialBin:

  cmp dword [di], 'INIT'
  jne nextFile

  cmp dword [di+4], 'IAL '
  jne nextFile

  cmp dword [di+8], 'BIN '
  jne nextFile


  jmp InitialBinFound
  nextFile:
    cmp di, 0x9000
    ja BootLoaderEnd
    add di, 32
    jmp SeekTheInitialBin

InitialBinFound:
  ; 打印 'Get Initial!'
  mov si, InitialFound
  call PrintString

  ;获取文件长度
  mov ax, [di+0x1c]
  mov dx, [di+0x1e]

  ;文件长度是字节为单位的，需要先除以512得到扇区数
  mov cx, 512
  div cx

  ;如果余数不为0，则需要多读一个扇区
  cmp dx, 0
  je NoRemainder

  ;ax是要读取的扇区数
  inc ax
  mov [BlockCount], ax  ; 设置参数值

  NoRemainder:
    ;文件起始簇号，也是转为扇区号，乘以8即可
    mov ax, [di+0x1a]
    sub ax, 2
    mov cx, 8
    mul cx

    ;现在文件起始扇区号存在 dx:ax ，直接保存到 ebx ，这个起始是相对于 DataBase 0x32,72 
    ;所以待会计算真正的起始扇区号还需要加上DataBase
    and eax, 0x0000ffff                ;
    add ebx, eax                       ;
    mov ax, dx                         ;
    shl eax, 16                        ;
    add ebx, eax                       ; 
    mov [BlockLow], ebx                ; 扇区号
    mov word [BufferOffset], 0x9000    ; 内存地址: 把磁盘数据加载到地址 0x9000 处
    call ReadDisk

    ; 打印 'Go to Initial!' 
    mov si, GotoInitial
    call PrintString

    ; 跳转到 Initial.bin 继续执行
    mov di, 0x9000                     ; 
    jmp di

ReadDisk:
  mov ah, 0x42  ; 操作码: 0x42 读，0x43 写
  mov al, 0x00  ; 在写操作时有意义: 0 无校验，1 写校验
  mov dl, 0x80  ; 0x80 代表第一块磁盘驱动器 
  mov si, DiskAddressPacket ; 磁盘地址报文
  int 0x13

  ; 检查返回值是否为 0 
  test ah, ah

  ; 报错
  mov byte [ShitHappens+0x06], 0x33
  jnz BootLoaderEnd
  ret

;打印以0x0a结尾的字符串
PrintString:
  push ax   ; 保存现场，函数内用于存储 临时字符
  push cx   ; 保存现场，函数内用于存储 循环变量
  push si   ; 函数入参

  mov cx, 512 ; 最多显示 512 个字符，超过会忽略
  PrintChar:
    // BIOS 中断 INT 0x10 有很多不同的功能，各个功能的入口是通过 CPU 寄存器 AH 的值来决定的，
    // 比如在 Teletype 模式下显示字符的功能号就是 0E 。
    //
    // 入口参数：
    //  AH＝0EH
    //  AL＝字符
    //  BH＝页码
    //  BL＝前景色(图形模式)
    // 
    // 使用方法：
    //  使用移位 mov 指令将 16 进制数 0x0E 移至 CPU 寄存器 AH 上，
    //  将要显示的字符移至 CPU 寄存器 AL 上，然后再通过 int 0x10 触发中断输出至屏幕。
    // 
    mov al, [si]  ; 
    mov ah, 0x0e  ; 
    int 0x10      ; 

    // 字符串尾
    cmp byte [si], 0x0a ; ASCII 码: '\n' => 10 => 0x0a
    je Return

    // 打印下一个字符
    inc si
    loop PrintChar

  Return:
    pop si
    pop cx
    pop ax
    ret

BootLoaderEnd:
  mov si, ShitHappens ; 参数
  call PrintString    ; 函数
  hlt                 ; CPU 进入暂停状态

; https://code.google.com/archive/p/xl-os/wikis/INT_13H.wiki
; 
; 使用拓展 int 13h 读取硬盘的结构体 DAP 
;
; 用预先定义的结构体来传递 disk address packet 参数给 int 13 。
;
;
; 数据类型
;   BYTE  1 字节整型 ( 8 位 )
;   WORD  2 字节整型 ( 16 位 )
;   DWORD 4 字节整型 ( 32 位 )
;   QWORD 8 字节整型 ( 64 位 )
;
; 磁盘地址数据包 Disk Address Packet (DAP)
;   
;   DAP 是基于绝对扇区地址的，因此利用 DAP，Int13H 可以轻松地逾越 1024 柱面的限制，因为它根本就不需要 CHS 的概念。
;   
;   DAP 的结构如下： 
;     struct DiskAddressPacket { 
;       BYTE PacketSize;  // 数据包尺寸(16字节) 
;       BYTE Reserved;    // ==0 
;       WORD BlockCount;  // 要传输的数据块个数(以扇区为单位) 
;       DWORD BufferAddr; // 传输缓冲地址(segment:offset) 
;       QWORD BlockNum;   // 磁盘起始绝对块地址 
;     };

;   PacketSize 保存了 DAP 结构的尺寸，以便将来对其进行扩充。在目前使用的扩展 Int13H 版本中 PacketSize 恒等于 16。 如果它小于16，扩展 Int13H 将返回错误码( AH=01，CF=1 )。
;   BlockCount 对于输入来说是需要传输的数据块总数，对于输出来说是实际传输的数据块个数。 
;   BlockCount = 0 表示不传输任何数据块。 
;   BufferAddr 是传输数据缓冲区的 32 位地址 (段地址:偏移量)。 数据缓冲区必须位于常规内存以内(1M)。 
;   BlockNum 表示的是从磁盘开始算起的绝对块地址(以扇区为单位)，与分区无关。第一个块地址为 0。 
;
;   一般来说，BlockNum 与 CHS 地址的关系是： 
;     BlockNum = ( cylinder * NumberOfHeads + head ) * SectorsPerTrack + sector - 1 
;   其中 cylinder，head，sector 是 CHS 地址，NumberOfHeads 是磁盘的磁头数， SectorsPerTrack 是磁盘每磁道的扇区数，
;   也就是说 BlockNum 是沿着 扇区->磁道->柱面 的顺序记数的。 
;   这一顺序是由磁盘控制器虚拟的，磁盘表面数据块的实际排列顺序可能与此不同，(如为了提高磁盘速度而设置的间隔因子将会打乱扇区的排列顺序)。
;
; 读入的 buffer 结构，用 c 描述为：
; struct buffer_packet
; {
;     short buffer_packet_size;         /* struct's size（可以为 0x10 或 0x18）*/
;     short sectors;                    /* 读多少个 sectors */
;     char *buffer;                     /* buffer address */
;     long long start_sectors;          /* 从哪个 sector 开始读 */
;     long long *l_buffer;              /* 64 位的 buffer address */
; } buffer;
;
; 这个 buffer_packet 结构大小可以为 16 bytes 或者 24 bytes
; 当 buffer_packet_size 设置为 0x10，最后的 l_buffer 无效。
; buffer_packet_size 设为 0x18 时，l_buffer 需要提供。
; 
; 注意：
;  buffer_packet 结构里的 buffer 地址，它是个逻辑地址，即：segment:offset
;  低 word 放着 offset 值，高 word 放着 segment 值。
;
;
;
DiskAddressPacket:
  PackSize      db 0x10       ;包大小，目前恒等于 16 字节，0x00
  Reserved      db 0          ;保留字节，恒等于0，0x01
  BlockCount    dw 0          ;要传输的数据块个数，0x02 
  BufferOffset  dw 0          ;目标内存地址的偏移，0x04
  BufferSegment dw 0          ;目标内存地址的段，让它等于 0 ，0x06
  BlockLow      dd 0          ;磁盘起始绝对地址，扇区为单位，这是低字节部分，0x08
  BlockHigh     dd 0          ;这是高字节部分，0x0c

ImportantTips:
  BootLoaderStart   db 'Start Booting!'
                    db 0x0d, 0x0a   ; \r\n 0a0d
  PartitionFound    db 'Get Partition!'
                    db 0x0d, 0x0a
  InitialFound      db 'Get Initial!'
                    db 0x0d, 0x0a
  GotoInitial       db 'Go to Initial!'
                    db 0x0d, 0x0a
  ShitHappens       db 'Error 0, Shit happens, check your code!'
                    db 0x0d, 0x0a
;结束为止
  times 446-($-$$) db 0

  
