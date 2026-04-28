/******************************************************************************
*
* 
* 
*
******************************************************************************/

/*****************************************************************************
*
* @file te_fsbl_hooks.c
*
*
******************************************************************************/


#include "fsbl.h"
#include "xstatus.h"
//rename to correct board name
#include "te_fsbl_hooks_te0726.h"

#include "xparameters.h"
#include "xil_hal.h"
#include "sleep.h"
// MC start
#include "xgpiops.h"
// MC stop

#define ENABLE_CAMERA
#define DIRECT_CAMERA_VIEW

#ifdef DIRECT_CAMERA_VIEW
#define HDMI_FB_ADDR			0x1FC00000
#define CAMERA_FB_ADDR			0x1FC00000
#endif

#ifndef DIRECT_CAMERA_VIEW
#define HDMI_FB_ADDR			0x1FC00000
#define CAMERA_FB_ADDR			0x1F800000
#endif

// MC start
#define HIGH 1
#define LOW 0
#define OUTPUT 1
#define INPUT 0

#define MIO7 7
// MC stop                    

/************************** Variable Definitions *****************************/


/************************** Function Prototypes ******************************/


/******************************************************************************
* This function is the hook which will be called  before the bitstream download.
* The user can add all the customized code required to be executed before the
* bitstream download to this routine.
*
* @param None
*
* @return
*		- XST_SUCCESS to indicate success
*		- XST_FAILURE.to indicate failure
*
****************************************************************************/
u32 TE_FsblHookBeforeBitstreamDload_Custom(void)
{
	u32 Status;

	Status = XST_SUCCESS;
  
    xil_printf("\r\n--------------------------------------------------------------------------------\r\n");
    xil_printf("TE0726 TE_FsblHookBeforeBitstreamDload_Custom\r\n"); 
	/* Add the code here */
    xil_printf("\r\n--------------------------------------------------------------------------------\r\n");


	return (Status);
}

/******************************************************************************
* This function is the hook which will be called  after the bitstream download.
* The user can add all the customized code required to be executed after the
* bitstream download to this routine.
*
* @param None
*
* @return
*		- XST_SUCCESS to indicate success
*		- XST_FAILURE.to indicate failure
*
****************************************************************************/
u32 TE_FsblHookAfterBitstreamDload_Custom(void)
{
	u32 Status;

	Status = XST_SUCCESS;

    xil_printf("\r\n--------------------------------------------------------------------------------\r\n");
    xil_printf("TE0726 TE_FsblHookAfterBitstreamDload_Custom\r\n"); 
	/* Add the code here */
    xil_printf("\r\n--------------------------------------------------------------------------------\r\n");

	return (Status);
}

/******************************************************************************
* This function is the hook which will be called  before the FSBL does a handoff
* to the application. The user can add all the customized code required to be
* executed before the handoff to this routine.
*
* @param None
*
* @return
*		- XST_SUCCESS to indicate success
*		- XST_FAILURE.to indicate failure
*
****************************************************************************/
u32 TE_FsblHookBeforeHandoff_Custom(void)
{
	u32 Status;

	Status = XST_SUCCESS;
  
  // MC start
  //----------- USB PHY RESET -------------------------------------

  XGpioPs_Config *config;
  XGpioPs usb_rst;

  config = XGpioPs_LookupConfig(XPAR_PS7_GPIO_0_DEVICE_ID);
  XGpioPs_CfgInitialize(&usb_rst, config, config->BaseAddr);
  XGpioPs_SetDirectionPin(&usb_rst, MIO7, OUTPUT);
  xil_printf("\r\n--------------------------------------------------------------------------------\r\n");
  xil_printf("USB PHY and USB HUB reset\r\n");
  xil_printf("\r\n--------------------------------------------------------------------------------\r\n");
  XGpioPs_WritePin(&usb_rst, MIO7, LOW);
  sleep(0.1);
  XGpioPs_WritePin(&usb_rst, MIO7, HIGH);
  //----------------------------------------------------------------  
  // MC stop

	return (Status);
}


/******************************************************************************
* This function is the hook which will be called in case FSBL fall back
*
* @param None
*
* @return None
*
****************************************************************************/
void TE_FsblHookFallback_Custom(void)
{
  
    xil_printf("\r\n--------------------------------------------------------------------------------\r\n");
    xil_printf("TE0726 TE_FsblHookFallback_Custom\r\n"); 
	/* Add the code here */
    xil_printf("\r\n--------------------------------------------------------------------------------\r\n");
  
  
	//while(1);
}


