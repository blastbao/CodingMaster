;***********************************************
;代码作者：谭玉刚
;教程链接：
;https://www.bilibili.com/video/BV1Lp4y1h7vg/
;https://www.youtube.com/watch?v=wbeLHALXRPw
;不要错过：
;B站/微信/油管/头条/知乎/大鱼/企鹅：谭玉刚
;百度/微博：玉刚谈
;来聊天呀：1054728152（QQ群）
;***********************************************


; 常量
NUL       equ 0x00
SETCHAR   equ 0x07
VIDEOMEM  equ 0xb800
STRINGLEN equ 0xffff

; 代码段
section code align=16 vstart=0x7c00
  mov si, SayHello
  xor di, di
  call PrintString
  mov si, SayByeBye
  call PrintString
  jmp End

PrintString:
  .setup:
  mov ax, VIDEOMEM    ; 显存基址
  mov es, ax

  mov bh, SETCHAR     ; 显示模式
  mov cx, STRINGLEN   ; 字符数

  .printchar:
  ; 取当前字符
  mov bl, [ds:si]
  inc si ; si += 1

  ; 写入字符到显存
  mov [es:di], bl
  inc di ; di += 1
  ; 写入模式到显存
  mov [es:di], bh
  inc di ; di += 1

  or bl, NUL
  jz .return
  loop .printchar
  .return:
  ret

SayHello  db 'Hi there,I am Coding Master!'
          db 0x00  ; "\0"
SayByeBye db 'I think you can handle it,bye!'
          db 0x00 ; "\0"

End: jmp End
times 510-($-$$) db 0
                 db 0x55, 0xaa    