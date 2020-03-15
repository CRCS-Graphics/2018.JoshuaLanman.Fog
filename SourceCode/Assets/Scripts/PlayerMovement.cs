/**********************************************************************************************
* File:         PlayerMovement.cs
* Developer:    Joshua Lanman
* Date:         December 1, 2018
* Description:  This script, when attached to the player gameObject with attached scene camera,
*               allows for moving the camera around the scene using simple keyboard and mouse.
**********************************************************************************************/
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class PlayerMovement : MonoBehaviour
{
    [SerializeField] private float Speed = 20;
    [SerializeField] private float XSensitivity = 1;
    [SerializeField] private float YSensitivity = 1;

    // Use this for initialization
    void Start()
    {

    }

    // Update is called once per frame
    void Update()
    {
        // Determine new look direction based on mouse movements
        float yRot = Input.GetAxisRaw("Mouse X") * XSensitivity;
        float xRot = Input.GetAxisRaw("Mouse Y") * YSensitivity;

        // Are we walking or running?
        var curMoveSpeed = Speed;
        if (Input.GetKey(KeyCode.LeftShift))
        {
            curMoveSpeed *= 2;
        }

        // Determine the new position and orientation/look direction
        transform.position += Camera.main.transform.forward * curMoveSpeed * Input.GetAxis("Vertical") * Time.deltaTime;
        transform.position += Camera.main.transform.right * curMoveSpeed * Input.GetAxis("Horizontal") * Time.deltaTime;
        transform.localRotation *= Quaternion.Euler(0f, yRot, 0f);

        // Update the camera orientation/look direction
        var cameras = gameObject.GetComponentsInChildren<Camera>();
        foreach (var cam in cameras)
        {
            cam.transform.localRotation *= Quaternion.Euler(-xRot, 0f, 0f);
        }
    }  
}
