
!include "MUI2.nsh"

Name    "�ǴϿ���" ; ���� �̸�
OutFile "installer.exe" ; ��ġ ���� �̸�

!define	GAME_NAME     "�ǴϿ���" ; ���� �̸�
!define GAME_EXEFILE  "�ǴϿ���.exe" ; ���� ���� ���� �̸�
!define GAME_TARGET_FOLDER "nooslab\piniengine" ; ���� ���� �̸�
!define GAME_SOURCE_FOLDER "Master" ; ���� ���� �̸�
!define	GAME_HELPFILE "Help.txt" ; ���� ���� ���� �̸�
!define GAME_LICENSE  "EULA.txt" ; ���̼��� ����
!define GAME_FINISHPAGE_RUN_TEXT "${GAME_NAME}�� �����մϴ�."
!define GAME_FINISHPAGE_SHOWREADME_TEXT "������ Ȯ���մϴ�."

!include "Main.nsh"
